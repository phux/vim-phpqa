" ------------------------------------------------------------------------------
" Exit when already loaded (or "compatible" mode set)
if exists("g:loaded_phpqa") || &cp
  finish
endif
let g:loaded_phpqa= 1
let s:keepcpo           = &cpo
set cpo&vim

" ---------------------------------------------------------------------
" Functions: {{{1

let s:num_signs = 0
let s:signName = ""

"
" the following lets user's define their own signs
"

let v:errmsg = ""
silent! sign list QuickHighMakeError
if "" != v:errmsg
    sign define QuickHighMakeError linehl=Error text=ER texthl=Error
endif

let v:errmsg = ""
silent! sign list QuickHighMakeWarning
if "" != v:errmsg
    sign define QuickHighMakeWarning linehl=WarningMsg text=WR texthl=WarningMsg
endif

let v:errmsg = ""
silent! sign list QuickHighGrep
if "" != v:errmsg
    sign define QuickHighGrep linehl=tag text=GR texthl=tag
endif


"
" Description:
" This routine allows the user to remove all signs and then add them back
" (i.e. toggle the state).  This could be useful if they want to inspect a
" line with the original syntax highlighting.
"
fun! phpqa#ToggleSigns()
    if "" == s:signName
        echohl ErrorMsg | echo "You must first run :Make or :Grep." | echohl None
        return
    endif

    if "" == s:error_list
        return
    endif

    if 0 == s:num_signs
        call s:AddSignsWrapper("all")
    else
        call phpqa#RemoveSigns("keep")
    endif
endfunction

"
" Description:
" This routine will get rid of all the signs in all open buffers.
"
fun! phpqa#RemoveSigns(augroup)
    while 0 != s:num_signs
        sign unplace 4782
        let s:num_signs = s:num_signs - 1
    endwhile

    let last_buffer = bufnr("$")
    let buf = 1
    while last_buffer >= buf
        call setbufvar(buf, "quickhigh_plugin_processed", 0)

        let buf = buf + 1
    endwhile

    if "discard" == a:augroup
        call s:RemoveAutoGroup()
        let s:error_list = ""
        if has("perl")
            perl "our %error_hash = ();"
        endif
    endif

    return
endfunction

"
" Description:
" This routine should be called after a make or grep.  (Like in the :Make and
" :Grep provided commands).
"
" It takes care of parsing the clist from vim, adding signs to all open
" buffers, and setting up autocmds.  The autocmds are used to add signs to new
" files once they're opened (e.g. if the user does a 'grep' and then does a
" :cn into a file not already open).
"
function phpqa#Init(sign)
    " else we need to add the error signs
    if 0 != s:num_signs
        echohl ErrorMsg | echo "There are still signs leftover.  Try removing first." | echohl None
        return
    endif

    let sign = a:sign

    let s:signName = sign

    " don't add anything if there's nothing to add
    if -1 == s:MakeErrorList()
        echohl ErrorMsg | echo "No errors." | echohl None
        return
    endif

    call s:AddSignsWrapper("all")
    call s:SetupAutogroup()
endfunction

"
" Description:
" This routine will get the clist and then parse that into a error list.
"
" The retrieval and parsing of the clist are separate for easier debugging.
"
function s:MakeErrorList()
    if -1 == s:GetClist()
        return -1
    endif
    " for debugging:
    " let s:clist = system("cat quickhigh.clist.file")

    return s:ParseClist()
endfunction

"
" Description:
" This routine retrieves the clist from vim.
"
function s:GetClist()
    let ABackup = @a
    let v:errmsg = ""

    " echo "redir start: " . strftime("%c")
    redir @a
    silent! clist
    redir END
    " echo "redir end: " . strftime("%c")

    let errmsg = v:errmsg
    let s:clist = @a
    let @a = ABackup

    if "" != errmsg
        if -1 != match(errmsg, '^E\d\+ No Errors')
            echohl ErrorMsg | echo errmsg | echohl None
        endif

        return -1
    endif

    return 1
endfunction

"
" Description:
" This routine initializes the error list.  The error list is basically the
" the clist in a more managable form.
"
" example clist:
"
" 3 main.c:75: warning: passing arg 3 of ...blah...
" 4 main.c:70: warning: it is tuesday this will fail
" 7 blue.c:7: programer is stupid
"
" would turn into (assuming the user setup their re's):
"
" QuickHighMakeWarning:/path/main.c:75:
" QuickHighMakeWarning:/path/main.c:70:
" QuickHighMakeError:/path/blue.c:7:
"
function s:ParseClist()
    " reset the error list
    let s:error_list = ""

    let sign = s:signName

    if has("pe")
        execute "perl &ParseClist(" . sign . ")"
    else

        let errorend = strlen(s:clist) - 1
        let partend = -1
        while (1)
            let partstart = partend + 1
            let partend = match(s:clist, "\n\\|$", partstart + 1)
            " echo strpart(s:clist, partstart, (partend - partstart))

            let fstart = match(s:clist, '\h', partstart)   " skip the error number
            let fend   = match(s:clist, ':',  fstart)
            let lstart = fend + 1
            let lend   = match(s:clist, ':', lstart)

            " echo "fstart: " . fstart
            " echo "fend: " . fend
            " echo "lstart: " . lstart
            " echo "lend: " . lend

            " check if done processing
            if -1 == fstart || -1 == fend || -1 == lstart || -1 == lend
                break
            endif

            " check if we got an invalid line
            if fstart >= partend || fend >= partend || lstart >= partend || lend >= partend
                continue
            endif

            let file = fnamemodify(strpart(s:clist, fstart, (fend-fstart)), ':p')
            let line = strpart(s:clist, lstart, (lend - lstart))
            let line = substitute(line, '\(\d*\).*', '\1', '')

            " echo "file: " . file
            " echo "line: " . line

            "if "QuickHighGrep" != sign
            "    let sign = s:GetSign(strpart(s:clist, lend, (partend - lend)))
            "endif

            let s:error_list = s:error_list . sign . "¬" . file . "¬" . line . "¬"
        endwhile
    endif

    " try and conserve memory
    let s:clist = ""

    if "" == s:error_list
        return -1
    else
        return 1
    endif
endfunction

"
" Description:
" This routine tries to figure out what sign goes on a particular line.  It is
" a separate function so perl can call it.
"
function s:GetSign(line)
    if exists("b:quickhigh_error_re") && -1 != match(a:line, b:quickhigh_error_re)
        let sign = "QuickHighMakeError"
    elseif exists("b:quickhigh_warning_re") && -1 != match(a:line, b:quickhigh_warning_re)
        let sign = "QuickHighMakeWarning"
    else
        let sign = "QuickHighMakeError"
    endif

    return sign
endfunction

"
" Description:
" This routine is called when the user wants to add signs in their files.  It
" will add signs in all buffers or just the current buffer.
"
function s:AddSignsWrapper(which)
    let cur_buf = bufname("%")

    echohl ErrorMsg | echo "Buffer: ".cur_buf | echohl None
    " in case we're called in the error list window or something
    if "" == cur_buf && "current" == a:which
        return
    endif

    if exists("b:quickhigh_plugin_processed")
        if 1 == b:quickhigh_plugin_processed
            return
        endif
    endif

    if "QuickHighGrep" == s:signName
        call s:AddSignsActual(a:which, "QuickHighGrep")

    " this is how we give preference to errors if a line has both warnings and errors.
    else
        call s:AddSignsActual(a:which, s:signName)
        "call s:AddSignsActual(a:which, "QuickHighMakeWarning")
        "call s:AddSignsActual(a:which, "QuickHighMakeError")
    endif
endfunction

"
" Description:
" This routine does the actual work of parsing the error list and adding signs
" (if appropriate).
"
" 4782 is a just a random number so we won't clash with anyone else's id
"
function s:AddSignsActual(which, sign)
    echohl ErrorMsg | echo "using sign ".a:sign | echohl None
    if has("rl")
        echohl ErrorMsg | echo "running perl with sign ".a:sign | echohl None
        execute "perl &AddSignsActual('" . a:which . "', '" . a:sign . "')"
        " echo "perl end: " . strftime("%c")
        return
    endif

    let add_ok  = 0
    let cur_buf = bufname("") 
        echohl ErrorMsg | echo "current buffer: ".cur_buf | echohl None

    " sign1:file1:line1:sign2:file2:line2:
    let pos = 0
    while (1)
        let send = match(s:error_list, '¬', pos)
        if -1 == send
            break
        endif
        echohl ErrorMsg | echo s:error_list." from ".pos." + ".(send-pos) | echohl None
        let sign = strpart(s:error_list, pos, (send - pos))

        if a:sign == sign
            echohl ErrorMsg | echo "signs are equal!" | echohl None
            let pos  = send + 1
            let fend = match(s:error_list, '¬', pos)
            let file = strpart(s:error_list, pos, (fend - pos))

            let pos  = fend + 1
            let lend = match(s:error_list, '¬', pos)
            let line = strpart(s:error_list, pos, (lend - pos))
            let pos  = lend + 1

                let add_ok = 1

            if "all" == a:which
                let add_ok = 1
            else
            endif

            " only add signs for files that are loaded
            if add_ok
                echohl ErrorMsg | echo "adding sign ".sign ." to buffer ".cur_buf | echohl None
                " echo "sign place 4782 name=" . sign . " line=" . line . " file=" . file
                exe ":sign place 4782 name=" . sign . " line=" . line . " file=\".expand(\"%:p\")"
                let s:num_signs = s:num_signs + 1
                "call setbufvar(bufname(file), "quickhigh_plugin_processed", 1)
            endif

        else
            let pos  = match(s:error_list, '¬', send + 1) " skip file
            let pos  = match(s:error_list, '¬', pos + 1)  " skip line
            let pos  = pos + 1
        endif
    endwhile
endfunction

"
" Description:
" These routines manipulate the autocmds used to add signs into files that are
" newly opened.
"
function s:SetupAutogroup()
    augroup QuickHigh
        autocmd BufReadPost * call s:AddSignsWrapper("current")
    augroup END
endfunction

function s:RemoveAutoGroup()
    augroup QuickHigh
        autocmd!
    augroup END

    augroup! QuickHigh
endfunction

if exists("quickhigh_plugin_debug")
function QuickhighDebug()
    redir > quickhigh.clist.file
    silent! clist
    redir END

    redir > quickhigh.vars
    let out = "b:quickhigh_warning_re = "
    if exists("b:quickhigh_warning_re")
        silent! echo out . b:quickhigh_warning_re
    else
        silent! echo out . "NOT DEFINED"
    endif

    let out = "b:quickhigh_error_re = "
    if exists("b:quickhigh_error_re")
        silent! echo out . b:quickhigh_error_re
    else
        silent! echo out . "NOT DEFINED"
    endif

    silent! echo "s:signName = " . s:signName
    redir END
endfunction
endif

" vim: ts=4 sw=4 et sts=4
