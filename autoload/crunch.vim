"HEADER{{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"Maintainer: Ryan Carney arecarn@gmail.com
"Repository: https://github.com/arecarn/crunch
"License: WTFPL

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}
"SCRIPT SETTINGS                                                           {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let save_cpo = &cpo   " allow line continuation
set cpo&vim

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}
"GLOBALS                                                                   {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
if !exists("g:crunch_calc_prompt")
    let g:crunch_calc_prompt = 'Calc >> '
endif
if !exists("g:crunch_calc_comment")
    let g:crunch_calc_comment = '"'
endif

let s:variables = {} 
let s:validVariable = '\v[a-zA-Z_]+[a-zA-Z0-9_]*'

"Number Regex Patterns
let sign = '\v[-+]?'
let number = '\v\.\d+|\d+%([.]\d+)?'
let eNotation = '\v%([eE][+-]?\d+)?'
let s:numPat = sign . '%(' . number . eNotation . ')' 

let s:ErrorTag = 'Crunch error: '
let s:isExclusive = 0
let s:bang = ''

let g:crunch_debug = 0

"default is append
if !exists("g:crunch_result_type_append")
    let g:crunch_result_type_append  = 1
endif

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

"MAIN FUNCTIONS{{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"crunch#Crunch()                                                          {{{2
"When called opens a command window prompt for an equation to be evaluated
"Optionally can take input as a argument before opening a prompt
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! crunch#Crunch(input)
    if a:input != ''
        let expr = a:input
    else
        let expr = s:GetInputString()
        redraw
    endif

    try
        if s:ValidLine(expr) == 0 | return | endif
        let result = crunch#core(expr)

        echo expr." = ".result

        if has('clipboard')
            echo "Yanked Result"
            "yank the result into the correct register
            if match(&clipboard, '\C\vunnamed') != -1
                call setreg('*', result, 'c')
            endif 
            if match(&clipboard, '\C\vunnamedplus') != -1
                call setreg('+', result, 'c')
            endif 
            if match(&clipboard, '\C\vunnamedplus|unamed') == -1
                call setreg('"', result, 'c')
            endif
        endif

    catch /Crunch error: /
        call s:EchoError(v:exception)
    endtry
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"crunch#Main()                                                            {{{2
" Captures the range for later use, Handles arguments, and then calls
" EvalLine
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! crunch#Main(args) range
    call crunch#debug#PrintMsg(a:args. ' = the Argument(s)')

    call s:HandleArgs(a:args, a:firstline, a:lastline)

    execute a:firstline.','.a:lastline.'call crunch#EvalLine()'
    call crunch#debug#PrintMsg('Exclusive cleared')
    let s:isExclusive = 0
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"crunch#EvalLine()                                                        {{{2
" evaluates a line in a buffer, allowing for prefixes and suffixes
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! crunch#EvalLine()
    let origExpr = s:CrunchInit()
    try
        if s:ValidLine(origExpr) == 0 | return | endif
        let origExpr = s:RemoveOldResult(origExpr)
        let expr = s:ReplaceVariable(origExpr)
        let result  = crunch#core(expr)
    catch /Crunch error: /
        call s:EchoError(v:exception)
        let result= v:exception
    endtry

    call setline('.', s:prefix.origExpr.' = '.result.s:suffix)
    call crunch#debug#PrintMsg('['. result.'] is the result' )
    return result
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"crunch#EvalPar()                                                       {{{2
"Evaluates a paragraph, equivalent to vip<leader>cl
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! crunch#EvalPar(args)
    call crunch#debug#PrintHeader('Crunch Paragraph Debug')
    execute "normal! vip\<ESC>"
    let topline = line("'<")
    let bottomline = line("'>")

    call crunch#debug#PrintMsg('['.a:args.'] is the variable' )
    execute topline."," bottomline."call "."crunch#Main(a:args)"
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"crunch#Visual()                                                     {{{2
"Takes string or mathematical expressions delimited by new lines 
"evaluates "each line individually and saving variables when they occur
"Finally, pasting over the selection or range
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! crunch#Visual(exprs)
    call crunch#debug#PrintHeader('Inizilation')

    let exprList = split(a:exprs, '\n', 1)
    call crunch#debug#PrintVarMsg(string(exprList), 'List of expr')

    for i in range(len(exprList))
        try
            let origLine = exprList[i]
            let exprList[i] = s:CrunchInitt(exprList[i])
            call s:CaptureVariable(exprList[i])
            if s:ValidLine(exprList[i]) == 0 
                let exprList[i] = origLine
                continue 
            endif
            let exprList[i] = s:RemoveOldResult(exprList[i])
            let origExpr = exprList[i]
            let exprList[i] = s:MarkENotation(exprList[i])
            let exprList[i] = s:ReplaceCapturedVariable(exprList[i])
            let exprList[i] = s:ReplaceVariable2(exprList[i], i)
            let exprList[i] = s:UnmarkENotation(exprList[i])
            let result  = crunch#core(exprList[i])
        catch /Crunch error: /
            call s:EchoError(v:exception)
            let result= v:exception
        endtry
        let exprList[i] = s:BuildResult(origExpr, result) 
    endfor
    call crunch#debug#PrintMsg(string(exprList).'= the exprLinesList')
    let exprLines = join(exprList, "\n")
    call crunch#debug#PrintMsg(string(exprLines).'= the exprLines')
    let s:variables = {}
    return exprLines
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"crunch#Dev()                                                             {{{2
"The top level function that handles arguments and user input
"TODO: elaborate
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! crunch#Dev(count, firstLine, lastLine, cmdInput, bang)
    let cmdInputExpr  = s:HandleCmdInput(a:cmdInput, a:bang)

    if cmdInputExpr != '' "an expression was passed in
        " TODO only call this once if possible 03 May 2014
        call crunch#Crunch(cmdInputExpr) 
    else " no command was passed in
        " let range = s:GetSelectionOrLines(a:count, a:firstLine, a:lastLine)

        call s:Range.setType(a:count, a:firstLine, a:lastLine)
        call s:Range.capture()

        if s:Range.range == '' "no lines or Selection was returned
            call crunch#Crunch(s:Range.range)
        else
            call s:Range.overWrite(crunch#Visual(s:Range.range))
        endif
    endif
    let s:bang = '' "TODO refactor
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"crunch#core()                                                            {{{2
" The core functionality of crunch 
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! crunch#core(expression)
    let expr = s:FixMultiplication(a:expression)
    let expr = s:IntegerToFloat(expr)
    let expr = s:AddLeadingZero(expr)
    return s:EvalMath(expr)
endfunction
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
function! crunch#operator(type) "{{{2
    call crunch#debug#PrintHeader('Operator')
    " backup settings that we will change
    let sel_save = &selection
    let cb_save = &clipboard

    " make selection and clipboard work the way we need
    set selection=inclusive clipboard-=unnamed clipboard-=unnamedplus

    " backup the unnamed register, which we will be yanking into
    let reg_save = @@

    call crunch#debug#PrintVarMsg(string(a:type), 'Operator Selection Type')
    " yank the relevant text, and also set the visual selection (which will be reused if the text
    " needs to be replaced)
    if a:type =~ '^\d\+$'
        " if type is a number, then select that many lines
        silent exe 'normal! V'.a:type.'$y'

    elseif a:type =~ '^.$'
        " if type is 'v', 'V', or '<C-V>' (i.e. 0x16) then reselect the visual region
        silent exe "normal! `<" . a:type . "`>y"
        call crunch#debug#PrintMsg('catch all type')
        let type=a:type

    elseif a:type == 'block' 
        " block-based text motion
        silent exe "normal! `[\<C-V>`]y"
        call crunch#debug#PrintMsg('block type')
        let type=''

    elseif a:type == 'line'
        " line-based text motion
        silent exe "normal! `[V`]y"
        let type='V'
    else
        " char-based text motion
        silent exe "normal! `[v`]y"
        let type='v'
    endif



    let regtype = type
    call crunch#debug#PrintVarMsg(regtype, "the regtype")
    let repl = crunch#Visual(@@)

    " if the function returned a value, then replace the text
    if type(repl) == 1
        " put the replacement text into the unnamed register, and also set it to be a
        " characterwise, linewise, or blockwise selection, based upon the selection type of the
        " yank we did above
        call setreg('@', repl, regtype)
        " reselect the visual region and paste
        normal! gvp
    endif

    " restore saved settings and register value
    let @@ = reg_save
    let &selection = sel_save
    let &clipboard = cb_save
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2}}}

" INITILAZATION {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"s:CrunchInit()                                                           {{{2
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"Gets the expression from current line, builds the suffix/prefix regex if
"need, and  removes the suffix and prefix from the expression
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:CrunchInit()
    call crunch#debug#PrintHeader('Crunch Inizilation Debug')

    let expr = getline('.')

    if !exists('b:filetype') || &filetype !=# b:filetype
        let b:filetype = &filetype
        call crunch#debug#PrintMsg('filetype set, rebuilding prefix/suffix regex')
        call crunch#debug#PrintMsg('['.&filetype.']= filetype')
        call s:BuildLinePrefix()
        call s:BuildLineSuffix()
    endif

    let s:suffix = matchstr(expr, b:suffixRegex)
    let s:prefix = matchstr(expr, b:prefixRegex)
    let expr = s:RemovePrefixNSuffix(expr)

    return expr
endfunction
"s:CrunchInit()                                                           {{{2
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"Gets the expression from current line, builds the suffix/prefix regex if
"need, and  removes the suffix and prefix from the expression
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:CrunchInitt(expr)
    call crunch#debug#PrintHeader('Crunch Inizilation Debug')

    let expr = a:expr

    if !exists('b:filetype') || &filetype !=# b:filetype
        let b:filetype = &filetype
        call crunch#debug#PrintMsg('filetype set, rebuilding prefix/suffix regex')
        call crunch#debug#PrintMsg('['.&filetype.']= filetype')
        call s:BuildLinePrefix()
        call s:BuildLineSuffix()
    endif

    let s:suffix = matchstr(expr, b:suffixRegex)
    let s:prefix = matchstr(expr, b:prefixRegex)
    let expr = s:RemovePrefixNSuffix(expr)

    return expr
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:GetRange()                                                            {{{2
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:GetRange(count, firstLine, lastLine)
    call crunch#debug#PrintHeader('Get Range')
    if a:count == 0 "no range given extract from command call
        let range = ''
    else "visual range was given
        if g:crunchMode  =~ '\v\Cv||V'
            let range = s:GetVisualSelection()
            call crunch#debug#PrintVarMsg(range,'visual range')
        else "mark range was given or % 
            let range = join(getline(a:firstLine, a:lastLine), "\n") " search the range instead
            call crunch#debug#PrintVarMsg(range,'range')
        endif
    endif
    return range
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:GetVisualSelection()                                                  {{{2
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:GetVisualSelection()
    try
        let a_save = getreg('a')
        normal! gv"ay
        return @a
    finally
        call setreg('a', a_save)
    endtry
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:HandleCmdInput()                                                          {{{2
" test if there is an arg in the correct form.
" return the arg if it's valid otherwise an empty string is returned
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:HandleCmdInput(cmdInput, bang)
    call crunch#debug#PrintHeader('Handle Args')
    call crunch#debug#PrintVarMsg(a:cmdInput,'the cmdInput')

    " was there a bang after the command?
    let s:bang = a:bang

    " find command switches in the expression and extract them into a list 
    let options = split(matchstr(a:cmdInput, '\v^\s*(-\a+\ze\s+)+'), '\v\s+-')
    call crunch#debug#PrintVarMsg(string(options),'the options')

    " remove the command switches from the cmdInput
    let expr = substitute(a:cmdInput, '\v\s*(-\a+\s+)+', '', 'g')
    call crunch#debug#PrintVarMsg(expr,'the commandline expr')

    call s:SetOptions(options)

    return expr
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"s:HandleArgs()                                                           {{{2
"Interpret arguments to set flags accordingly
"TODO Remove me, I'm not sure this is still used 03 May 2014
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:HandleArgs(args, fline, lline)
    call crunch#debug#PrintHeader('Handle Arguments Debug')
    call crunch#debug#PrintMsg('['.a:args.']= the arguments')

    if a:args !=# ''
        let  s:firstline = a:fline
        let  s:lastline  = a:lline
        if a:args ==# '-exclusive' || a:args ==# '-exc'
            call crunch#debug#PrintMsg('Exclusive set')
            let s:isExclusive = 1
        else
            call s:EchoError(s:ErrorTag ."'".a:args."' is not a valid argument")
        endif
    endif
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:SetOptions()                                                          {{{2
" 
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:SetOptions(input)
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:GetValidArg()                                                          {{{2
" TODO is this function even needed?
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:GetValidArg(input)
    call crunch#debug#PrintHeader('Get Valid Arguments')
    let arg = matchstr( a:input, '\C\v^\s*-\zs\a+\ze(\s+|$)')
    call crunch#debug#PrintMsg('The search engine name is =['.arg.']')
    return arg
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2}}}

"FORMAT EXPRESSION{{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"s:ValidLine()                                                            {{{2
"Checks the line to see if it is a variable definition, or a blank line that
"may or may not contain whitespace.

"If the line is invalid this function returns false
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:ValidLine(expr)
    call crunch#debug#PrintHeader('Valid Line')
    call crunch#debug#PrintMsg('[' . a:expr . ']= the tested string' )

    "checks for commented lines
    if a:expr =~ '\v^\s*'.g:crunch_calc_comment
        call crunch#debug#PrintMsg('test1 failed comment')
        return 0
    endif

    " checks for empty/blank lines
    if a:expr =~ '\v^\s*$'
        call crunch#debug#PrintMsg('test2 failed blank line')
        return 0
    endif

    " checks for lines that don't need evaluation
    if a:expr =~ '\v\C^\s*'.s:validVariable.'\s*\=\s*-?\s*'.s:numPat.'\s*$'
        call crunch#debug#PrintMsg('test3 failed dosnt need evaluation')
        return 0
    endif
    call crunch#debug#PrintMsg('It is a valid line!')
    return 1
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"s:RemoveOldResult()                                                      {{{2
"Remove old result if any
"eg '5+5 = 10' becomes '5+5'
"eg 'var1 = 5+5 =10' becomes 'var1 = 5+5'
"inspired by Ihar Filipau's inline calculator
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:RemoveOldResult(expr)
    call crunch#debug#PrintHeader('Remove Old Result')

    let expr = a:expr
    "if it's a variable declaration with an expression ignore the first = sign
    "else if it's just a normal expression just remove it
    call crunch#debug#PrintMsg('[' . expr . ']= expression before removed result')

    let expr = substitute(expr, '\v\s*\=\s*('.s:numPat.')?\s*$', "", "")
    call crunch#debug#PrintMsg('[' . expr . ']= after removed old result')

    let expr = substitute(expr, '\v\s*\=\s*Crunch error:.*\s*$', "", "")
    call crunch#debug#PrintMsg('[' . expr . ']= after removed old error')

    let expr = substitute(expr, '\v^\s\+\ze?.', "", "")
    call crunch#debug#PrintMsg('[' . expr . ']= after removed whitespace')

    let expr = substitute(expr, '\v.\zs\s+$', "", "")
    call crunch#debug#PrintMsg('[' . expr . ']= after removed whitespace')

    return expr
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:FixMultiplication()                                                   {{{2
" turns '2sin(5)3.5(2)' into '2*sing(5)*3.5*(2)'
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:FixMultiplication(expr)
    call crunch#debug#PrintHeader('Fix Multiplication')

    "deal with ')( -> )*(', ')5 -> )*5' and 'sin(1)sin(1)'
    let expr = substitute(a:expr,'\v(\))\s*([(\.[:alnum:]])', '\1\*\2','g')
    call crunch#debug#PrintMsg('[' . expr . ']= fixed multiplication 1')

    "deal with '5sin( -> 5*sin(', '5( -> 5*( ', and  '5x -> 5*x'
    let expr = substitute(expr,'\v(\d)\s*([(a-df-zA-DF-Z])', '\1\*\2','g')
    call crunch#debug#PrintMsg('[' . expr . ']= fixed multiplication 2')

    return expr
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:IntegerToFloat()                                                      {{{2
" Convert Integers in the exprs to floats by calling a substitute
" command
" NOTE: from HowMuch.vim
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:IntegerToFloat(expr)
    call crunch#debug#PrintHeader('Integer to Float')
    call crunch#debug#PrintMsg('['.a:expr.']= before int to float conversion')
    let expr = a:expr 
    let expr = substitute(expr,'\(^\|[^.0-9]\)\zs\([eE]-\?\)\@<!\d\+\ze\([^.0-9]\|$\)', '&.0', 'g')
    call crunch#debug#PrintMsg('['.expr.']= after int to float conversion')
    return expr
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2}}}

" E NOTATION {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:MarkENotation(expr) "{{{2
    let expr = a:expr
    let number = '\v(\.\d+|\d+([.]\d+)?)\zs[eE]\ze[+-]?\d+'
    let expr = substitute(expr, number, '#', 'g')
    return expr
endfunction 

" 5#3
" 5#-3
function! s:UnmarkENotation(expr)
    let expr = a:expr
    call crunch#debug#PrintVarMsg(expr, 'before Unmarking E notation')
    "put back the e and remove the following ".0"
    let expr = substitute(expr, '\v#([-]?\d+)(\.0)?', 'e\1', 'g')
    call crunch#debug#PrintVarMsg(expr, 'after Unmarking E notation')
    return expr
endfunction!

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2}}}

" HANDLE VARIABLES{{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"s:CaptureVariables()                                                     {{{2
"TODO description
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:CaptureVariable(expr)
    call crunch#debug#PrintHeader('Capture Variable')

    let VarNamePat = '\v\C^\s*\zs'.s:validVariable.'\ze\s*\=\s*'
    let VarValuePat = '\v\=\s*\zs-?\s*'.s:numPat.'\ze\s*$' 

    let VarName = matchstr(a:expr, VarNamePat)
    let VarValue = matchstr(a:expr, VarValuePat)

    call crunch#debug#PrintVarMsg(VarName, 'the name of the variable')
    call crunch#debug#PrintVarMsg(VarValue, 'the value of the variable')

    if VarName != ''  && VarValue != ''
        let s:variables[VarName] = '('.VarValue.')'
        call crunch#debug#PrintVarMsg(string(s:variables), 'captured variables')
    endif

endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"s:ReplaceCapturedVariable()                                      {{{2
"Replaces the variable within an expression with the value of that variable
"inspired by Ihar Filipau's inline calculator
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:ReplaceCapturedVariable(expr)
    call crunch#debug#PrintHeader('Replace Captured Variablee')

    let expr = a:expr
    call crunch#debug#PrintMsg("[".expr."]= expression before variable replacement ")

    " strip the variable marker, if any
    let expr = substitute( expr, '\v\C^\s*'.s:validVariable.'\s*\=\s*', "", "")
    call crunch#debug#PrintMsg("[".expr."]= expression striped of variable")

    let variable_regex = '\v('.s:validVariable .'\v)\ze([^(a-zA-Z0-9_]|$)' "TODO move this up to the top
    " replace variable with it's value
    let expr = substitute(expr, variable_regex, 
                \ '\=s:GetVariableValue3(submatch(1))', 'g' )


    call crunch#debug#PrintMsg("[".expr."]= expression after variable replacement")
    return expr
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"s:ReplaceVariable()                                                      {{{2
"Replaces the variable within an expression with the value of that variable
"inspired by Ihar Filipau's inline calculator
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:ReplaceVariable(expr)
    call crunch#debug#PrintHeader('Replace Variable')

    let expr = a:expr
    call crunch#debug#PrintMsg("[".expr."]= expression before variable replacement ")

    " strip the variable marker, if any
    let expr = substitute( expr, '\v\C^\s*'.s:validVariable.'\s*\=\s*', "", "")
    call crunch#debug#PrintMsg("[".expr."]= expression striped of variable")

    " replace variable with it's value
    let expr = substitute( expr, '\v('.s:validVariable.
                \'\v)\ze([^(a-zA-Z0-9_]|$)',
                \ '\=s:GetVariableValue(submatch(1))', 'g' )

    call crunch#debug#PrintMsg("[".expr."]= expression after variable replacement")
    return expr
endfunction

function! s:GetVariableValue3(variable) abort
    let value = get(s:variables, a:variable, "not found")
    if value == "not found"
        " call s:Throw("value for ".a:variable." not found")
        return a:variable
    endif 

    return value
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"s:GetVariableValue()                                                     {{{2
"Searches for the value of a variable and returns the value assigned to the
"variable inspired by Ihar Filipau's inline calculator
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:GetVariableValue(variable)

    if a:variable =~ '\c^e\d*$'
        " TODO: make the E of e handling cleaner
        " if variable is e or E don't do anything
        return a:variable
    endif

    call crunch#debug#PrintHeader('Get Variable Value')
    call crunch#debug#PrintMsg("[".getline('.')."]= the current line")

    call crunch#debug#PrintMsg("[" . a:variable . "]= the variable")

    if s:isExclusive == 1
        call crunch#debug#PrintMsg("Searching with Stopline")
        call crunch#debug#PrintMsg("[".s:firstline."]= Stopline")
        let sline =search('\v\C^('.b:prefixRegex.
                    \ ')?\V'.a:variable.'\v\s*\=\s*', "bnW", (s:firstline -1))
    else
        let sline = search('\v\C^('.b:prefixRegex.
                    \ ')?\V'.a:variable.'\v\s*\=\s*' , "bnW")
    endif

    call crunch#debug#PrintMsg("[".sline."]= result of search for variable")
    if sline == 0
        call s:Throw("variable ".a:variable." not found")
    endif

    call crunch#debug#PrintMsg("[" .getline(sline). "]= line with variable value")
    let line = s:RemovePrefixNSuffix(getline(sline))
    call crunch#debug#PrintHeader('Get Variable Value Contiuned')

    let variableValue = matchstr(line,'\v\=\s*\zs-?\s*'.s:numPat.'\ze\s*$')
    call crunch#debug#PrintMsg("[" . variableValue . "]= the variable value")
    if variableValue == ''
        call s:Throw('value for '.a:variable.' not found')
    endif

    return '('.variableValue.')'
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2

"s:ReplaceVariable2()                                                      {{{2
"Replaces the variable within an expression with the value of that variable
"inspired by Ihar Filipau's inline calculator
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:ReplaceVariable2(expr, num)
    call crunch#debug#PrintHeader('Replace Variable 2')

    let expr = a:expr
    call crunch#debug#PrintMsg("[".expr."]= expression before variable replacement ")

    " strip the variable marker, if any
    let expr = substitute( expr, '\v\C^\s*'.s:validVariable.'\s*\=\s*', "", "")
    call crunch#debug#PrintMsg("[".expr."]= expression striped of variable")

    " replace variable with it's value
    let expr = substitute( expr, '\v('.s:validVariable.
                \'\v)\ze([^(a-zA-Z0-9_]|$)',
                \ '\=s:GetVariableValue2(submatch(1), a:num)', 'g' )

    call crunch#debug#PrintMsg("[".expr."]= expression after variable replacement")
    return expr
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"s:GetVariableValue2()                                                     {{{2
"Searches for the value of a variable and returns the value assigned to the
"variable inspired by Ihar Filipau's inline calculator
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:GetVariableValue2(variable, num)

    call crunch#debug#PrintMsg("[".s:Range.firstLine."]= is the firstline")
    call crunch#debug#PrintMsg("[".a:num."]= is the num")
    call crunch#debug#PrintMsg("[".a:variable."]= is the variable to be replaced")
    let sline = search('\v\C^('.b:prefixRegex.')?\V'.a:variable.'\v\s*\=\s*', 
                \"bnW" )

    call crunch#debug#PrintMsg("[".sline."]= search line")

    let line = s:RemovePrefixNSuffix(getline(sline))
    let variableValue = matchstr(line,'\v\=\s*\zs-?\s*'.s:numPat.'\ze\s*$')
    call crunch#debug#PrintMsg("[" . variableValue . "]= the variable value")
    if variableValue == ''
        call s:Throw("value for ".a:variable." not found")
    else
        return '('.variableValue.')'
    endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2}}}

" RESULT HANDLING{{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"s:BuildResult()                                                          {{{2
"Return Output
" append result (option: Append)
" replace result (option: Replace)
" append result of Statistical operation (option: Statistic)
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:BuildResult(expr, result)

    let output = a:expr .' = '. a:result

    " capture variable results if they exists TODO refactor
    call s:CaptureVariable(output) 

    " bang isn't used and type is not append result
    if (s:bang == '!' && g:crunch_result_type_append) 
                \|| (s:bang == '' && !g:crunch_result_type_append) 
        let output = a:result
    endif
    call crunch#debug#PrintVarMsg(s:prefix,"s:prefix")
    call crunch#debug#PrintVarMsg(s:suffix,"s:suffix")
    call crunch#debug#PrintVarMsg(output, "output")
    return s:prefix.output.s:suffix
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:AddLeadingZero()                                                      {{{2
" convert .5*.34 -> 0.5*0.34
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:AddLeadingZero(expr)
    let expr = a:expr
    call crunch#debug#PrintHeader('Add Leading Zero')
    call crunch#debug#PrintMsg('['.expr.']= before adding leading zero')
    let expr = substitute(expr,'\v(^|[^.0-9])\zs\.\ze([0-9])', '0&', 'g')
    call crunch#debug#PrintMsg('['.expr.']= after adding leading zero')
    return expr
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:OverWriteVisualSelection()                                            {{{2
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:OverWriteVisualSelection(input)
    "TODO handle ranges with marks and "%" 03 May 2014
    let a_save = @a
    if g:crunchMode  =~ '\C\vV|v|'
        call setreg('a', a:input, g:crunchMode)
    else
        call setreg('a', a:input, 'V')
    endif 
    normal! gv"ap
    let @a = a_save
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2}}}

"PREFIX/SUFFIX {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"s:RemovePrefixNSuffix()                                                  {{{2
"Removes the prefix and suffix from a string
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:RemovePrefixNSuffix(expr)
    let expr = a:expr
    call crunch#debug#PrintHeader('Remove Line Prefix and Suffix')

    call crunch#debug#PrintMsg('['.b:prefixRegex.']= the REGEX of the prefix/suffix')
    call crunch#debug#PrintMsg('['.b:suffixRegex.']= the REGEX of the suffix/suffix')
    call crunch#debug#PrintMsg('['.expr.']= expression BEFORE removing prefix/suffix')
    let expr = substitute(expr, b:prefixRegex, '', '')
    call crunch#debug#PrintMsg('['.expr.']= expression AFTER removing prefix')
    let expr = substitute(expr, b:suffixRegex, '', '')
    call crunch#debug#PrintMsg('['.expr.']= expression AFTER removing suffix')
    return expr
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"s:BuildLineSuffix()                                                      {{{2
"from a list of suffixes builds a regex expression for all suffixes in the
"list
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:BuildLineSuffix()
    call crunch#debug#PrintHeader('Build Line Suffix')
    call crunch#debug#PrintMsg( "[".&commentstring."]=  the comment string ")
    let s:commentEnd = matchstr(&commentstring, '\v.+\%s\zs.*')

    "Build the suffix

    "Valid Line suffix list
    let s:Linesuffixs = ["*","//", s:commentEnd]
    let b:suffixRegex = ''
    let NumberOfsuffixes = len(s:Linesuffixs)

    "TODO replace with join() + map()
    for suffix in s:Linesuffixs
        " call crunch#debug#PrintMsg( "[".suffix."]= suffix to be added to regex")
        let b:suffixRegex = b:suffixRegex.escape(suffix,'\/')
        if NumberOfsuffixes !=1
            let b:suffixRegex = b:suffixRegex.'\|'
        endif

        call crunch#debug#PrintMsg( "[".b:suffixRegex."]= REGEX for all the suffixes")
        let NumberOfsuffixes -= 1
    endfor
    let b:suffixRegex= '\V\s\*\('.b:suffixRegex.'\)\=\s\*\$\v'

    "NOTE: this regex is very non magic see :h \V
    call crunch#debug#PrintMsg("[".b:suffixRegex."]= REGEX for all the suffixes")
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"s:BuildLinePrefix()                                                      {{{2
"from a list of prefixes builds a regex expression for all prefixes in the
"list
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:BuildLinePrefix()

    call crunch#debug#PrintHeader('Build Line Prefix')
    call crunch#debug#PrintMsg( "[".&commentstring."]=  the comment string ")
    let s:commentStart = matchstr(&commentstring, '\v.+\ze\%s')

    "Build the prefix

    "Valid Line Prefix list
    let s:LinePrefixs = ["*","//", s:commentStart]
    let b:prefixRegex = ''
    let NumberOfPrefixes = len(s:LinePrefixs)


    "TODO replace with join() + map()
    for prefix in s:LinePrefixs
        " call crunch#debug#PrintMsg( "[".prefix."]= prefix to be added to regex")
        let b:prefixRegex = b:prefixRegex.escape(prefix,'\/')
        if NumberOfPrefixes !=1
            let b:prefixRegex = b:prefixRegex.'\|'
        endif

        call crunch#debug#PrintMsg( "[".b:prefixRegex."]= REGEX for the prefixes")
        let NumberOfPrefixes -= 1
    endfor
    let b:prefixRegex= '\V\^\s\*\('.b:prefixRegex.'\)\=\s\*\v'

    "NOTE: this regex is very non magic see :h \V
    call crunch#debug#PrintMsg("[".b:prefixRegex."]= REGEX for all the prefixes")
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" prompt the user for an expression
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:GetInputString()
    call inputsave()
    let expr = input(g:crunch_calc_prompt)
    call inputrestore()
    return expr
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2}}}

"EVALUATION {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"s:EvalMath()                                                             {{{2
"Return Output
" append result (option: Append)
" replace result (option: Replace)
" append result of Statistical operation (option: Statistic)
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:EvalMath(expr)
    "a function pointers to the eval method
    "if python
    "if octave
    "if vimscript
    let result = s:VimEval(a:expr)
    return result
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
" s:VimEval()                                                  {{{2
" Evaluates the expression and checks for errors in the process. Also
" if there is no error echo the result and save a copy of it to the default
" paste register
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:VimEval(expr)
    call crunch#debug#PrintHeader('Evaluate Expression')
    call crunch#debug#PrintMsg('[' . a:expr . "]= the final expression")

    let result = string(eval(a:expr))
    call crunch#debug#PrintMsg('['.result.']= before trailing ".0" removed')
    call crunch#debug#PrintMsg('['.matchstr(result,'\v\.0+$').']= trailing ".0"')

    "check for trailing '.0' in result and remove it (occurs with vim eval)
    if result =~ '\v\.0+$'
        let result = string(str2nr(result))
    endif

    return result
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2
"}}}

"ERRORS{{{
"s:EchoError()                                                            {{{2
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:EchoError(errorString)
    echohl WarningMsg
    echomsg a:errorString
    echohl None
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"s:Throw()                                                                {{{2
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function!  s:Throw(errorBody) abort
    let ErrorMsg = s:ErrorTag.a:errorBody
    throw ErrorMsg
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}2}}}

"RESTORE SETTINGS{{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let &cpo = save_cpo

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

"{{{ Range
let s:Range = { 'type' : "", 'range' : "", 'firstLine' : 0, 'lastLine' : 0 }

"public
function s:Range.setType(count, firstLine, lastLine) dict
    if a:count == 0 "no range given
        let self.type = "none"
    else "range was given
        if g:crunchMode =~ '\v\Cv|'
            let self.type = "selection"
        else "line wise mark, %, or visual line range given
            let self.type = "lines"
            let self.firstLine = a:firstLine
            let self.lastLine = a:lastLine
        endif
    endif
    call crunch#debug#PrintMsg(self.firstLine.'= first line')
    call crunch#debug#PrintMsg(self.lastLine.'= last line')
endfunction

"public
function s:Range.getType() dict
    return self.type
endfunction


"public
function s:Range.capture() dict
    if self.type == "selection"
        let self.range = self.getSelection()
    elseif self.type == "lines"
        let self.range = self.getLines()
    elseif self.type == "none"
        let self.range =""
    else
        call s:Throw("Invalid value for s:Range.type")
    endif
    call crunch#debug#PrintMsg(self.type.'= type of selection')
endfunction

"public
function s:Range.overWrite(rangeToPut) dict
    call crunch#debug#PrintHeader('Range.overWrite')
    let a_save = @a

    call crunch#debug#PrintVarMsg("pasting as", self.type)
    call crunch#debug#PrintVarMsg("pasting", a:rangeToPut)
    if self.type == "selection"
        call setreg('a', a:rangeToPut, g:crunchMode)
        normal! gv"ap
    elseif self.type == "lines"
        call setline(self.firstLine, split(a:rangeToPut, "\n"))
    else
        call s:Throw("Invalid value for s:Range.type call s:Range.setType first")
    endif

    let @a = a_save
endfunction

"private helper
function s:Range.getLines() dict
    return join(getline(self.firstLine, self.lastLine), "\n")
endfunction

"private helper
function s:Range.getSelection() dict
    try
        let a_save = getreg('a')
        normal! gv"ay
        return @a
    finally
        call setreg('a', a_save)
    endtry
endfunction

"}}}

" vim:foldmethod=marker
