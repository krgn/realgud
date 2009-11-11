;; -------------------------------------------------------------------
;; Dependencies.
;;
(eval-when-compile (require 'cl))
  
(require 'load-relative)
(provide 'pydbgr-core)
(load-relative 
 '("../dbgr-track" "../dbgr-core" "../dbgr-scriptbuf" "pydbgr-regexp") 
 'pydbgr-core)

(defvar dbgr-scriptbuf-info)
(defvar pydbgr-pat-hash)
(declare-function dbgr-cmdbuf-command-string (current-buffer))

;; FIXME: I think the following could be generalized and moved to 
;; dbgr-... probably via a macro.
(defvar pydbgr-minibuffer-history nil
  "minibuffer history list for the command `pydbgr'.")

(easy-mmode-defmap pydbgr-minibuffer-local-map
  '(("\C-i" . comint-dynamic-complete-filename))
  "Keymap for minibuffer prompting of gud startup command."
  :inherit minibuffer-local-map)

(defun pydbgr-query-cmdline (&optional opt-debugger opt-cmd-name)
  "Prompt for a pydbgr debugger command invocation to run.
Analogous to `gud-query-cmdline'"
  ;; FIXME: keep a list of recent invocations.
  (let ((debugger (or opt-debugger
		   (dbgr-scriptbuf-var-name pydbgr-scriptvar)))
	(cmd-name (or opt-cmd-name
		      (pydbgr-suggest-python-file))))
    (read-from-minibuffer
     (format "Run %s (like this): " debugger)  ;; prompt string
     (pydbgr-suggest-invocation debugger)      ;; initial value
     pydbgr-minibuffer-local-map               ;; keymap
     nil                                       ;; read - use default value
     pydbgr-minibuffer-history                 ;; history variable
     )))

(defun pydbgr-parse-cmd-args (orig-args)
  "Parse command line ARGS for the annotate level and name of script to debug.

ARGS should contain a tokenized list of the command line to run.

We return the a list containing
- the command processor (e.g. python) and it's arguments if any - a list of strings
- the name of the debugger given (e.g. pydbgr) and its arguments - a list of strings
- the script name and its arguments - list of strings
- whether the annotate or emacs option was given ('-A', '--annotate' or '--emacs) - a boolean

For example for the following input 
  (map 'list 'symbol-name
   '(python2.6 -O -Qold --emacs ./gcd.py a b))

we might return:
   ((python2.6 -O -Qold) (pydbgr --emacs) (./gcd.py a b) 't)

NOTE: the above should have each item listed in quotes.
"

  ;; Parse the following kind of pattern:
  ;;  [python python-options] pydbgr pydbgr-options script-name script-options
  (let (
	(args orig-args)
	(pair)          ;; temp return from 
	(python-opt-two-args '("c" "m" "Q" "W"))
	;; Python doesn't have mandatory 2-arg options in our sense,
	;; since the two args can be run together, e.g. "-C/tmp" or "-C /tmp"
	;; 
	(python-two-args '())
	;; One dash is added automatically to the below, so
	;; h is really -h and -host is really --host.
	(pydbgr-two-args '("x" "-command" "e" "-execute" 
			   "o" "-output"  "t" "-target"
			   "a" "-annotate"))
	(pydbgr-opt-two-args '())

	;; Things returned
	(script-name nil)
	(debugger-name nil)
	(interpreter-args '())
	(debugger-args '())
	(script-args '())
	(annotate-p nil))

    (if (not (and args))
	;; Got nothing: return '(nil, nil)
	(list interpreter-args debugger-args script-args annotate-p)
      ;; else
      ;; Strip off optional "python" or "python182" etc.
      (when (string-match "^python[-0-9.]*$"
			  (file-name-sans-extension
			   (file-name-nondirectory (car args))))
	(setq interpreter-args (list (pop args)))

	;; Strip off Python-specific options
	(while (and args
		    (string-match "^-" (car args)))
	  (setq pair (dbgr-parse-command-arg 
		      args python-two-args python-opt-two-args))
	  (nconc interpreter-args (car pair))
	  (setq args (cadr pair))))

      ;; Remove "pydbgr" from "pydbgr --pydbgr-options script
      ;; --script-options"
      (setq debugger-name (file-name-sans-extension
			   (file-name-nondirectory (car args))))
      (unless (string-match "^pydbgr$" debugger-name)
	(message 
	 "Expecting debugger name to be pydbgr"
	 debugger-name))
      (setq debugger-args (list (pop args)))

      ;; Skip to the first non-option argument.
      (while (and args (not script-name))
	(let ((arg (car args)))
	  (cond
	   ;; Annotation or emacs option with level number.
	   ((or (member arg '("--annotate" "-A"))
		(equal arg "--emacs"))
	    (setq annotate-p t)
	    (nconc debugger-args (list (pop args))))
	   ;; Combined annotation and level option.
	   ((string-match "^--annotate=[0-9]" arg)
	    (nconc debugger-args (list (pop args)) )
	    (setq annotate-p t))
	   ;; Options with arguments.
	   ((string-match "^-" arg)
	    (setq pair (dbgr-parse-command-arg 
			args pydbgr-two-args pydbgr-opt-two-args))
	    (nconc debugger-args (car pair))
	    (setq args (cadr pair)))
	   ;; Anything else must be the script to debug.
	   (t (setq script-name arg)
	      (setq script-args args))
	   )))
      (list interpreter-args debugger-args script-args annotate-p))))

(defun pydbgr-file-python-mode? (filename)
  "Return true if FILENAME is a buffer we are visiting a buffer
that is in python-mode"
  (let ((buffer (and filename (find-buffer-visiting filename)))
	(match-pos))
    (if buffer 
	(progn 
	  (save-current-buffer
	    (set-buffer buffer)
	    (setq match-pos (string-match "^python-" (format "%s" major-mode))))
	  (and match-pos (= 0 match-pos)))
      nil)))

;; FIXME generalize and put into dbgr-core.el
(defun pydbgr-suggest-invocation (debugger-name)
  "Suggest a rbdbgr command invocation. If the current buffer is
a process buffer that that `dbgr-invocation' set and we are in
rbdbgr-track-mode, then use the value of that variable. Otherwise
we try to find a suitable Ruby program using `rbdbgr-suggest-python-file' and
prepend the debugger name onto that. FIXME: should keep a list of
previously used invocations.
"
  (cond
   ((dbgr-cmdbuf-command-string (current-buffer)))
   ((dbgr-scriptbuf-command-string (current-buffer)))
   (t (concat debugger-name " " (pydbgr-suggest-python-file)))))

(defun pydbgr-suggest-python-file ()
    "Suggest a Python file to debug. First priority is given to the
current buffer. If the major mode is Python-mode, then we are
done. If the major mode is not Python, we'll use priority 2 and we
keep going.  Then we will try files in the default-directory. Of
those that we are visiting we will see if the major mode is Python,
the first one we find we will return.  Failing this, we see if the
file is executable and has a .rb suffix. These have priority 8.
Failing that, we'll go for just having a .rb suffix. These have
priority 7. And other executable files have priority 6.  Within a
given priority, we use the first one we find."
    (let* ((file)
	   (file-list (directory-files default-directory))
	   (priority 2)
	   (is-not-directory)
	   (result (buffer-file-name)))
      (if (not (pydbgr-file-python-mode? result))
	  (while (and (setq file (car-safe file-list)) (< priority 8))
	    (setq file-list (cdr file-list))
	    (if (pydbgr-file-python-mode? file)
		(progn 
		  (setq result file)
		  (setq priority 
			(if (file-executable-p file)
			    (setq priority 8)
			  (setq priority 7)))))
	    ;; The file isn't in a Python-mode buffer,
	    ;; Check for an executable file with a .rb extension.
	    (if (and file (file-executable-p file)
		     (setq is-not-directory (not (file-directory-p file))))
		(if (and (string-match "\.rb$" file))
		    (if (< priority 6)
			(progn
			  (setq result file)
			  (setq priority 6))))
	      (if (and is-not-directory (< priority 5))
		  ;; Found some sort of executable file.
		  (progn
		    (setq result file)
		    (setq priority 5))))))
      result))

(defun pydbgr-goto-traceback-line (pt)
  "Display the location mentioned by the Python traceback line
described by PT."
  (interactive "d")
  (goto-line-for-pt-and-type pt "traceback" pydbgr-pat-hash))

(defun pydbgr-reset ()
  "Pydbgr cleanup - remove debugger's internal buffers (frame,
breakpoints, etc.)."
  (interactive)
  ;; (pydbgr-breakpoint-remove-all-icons)
  (dolist (buffer (buffer-list))
    (when (string-match "\\*pydbgr-[a-z]+\\*" (buffer-name buffer))
      (let ((w (get-buffer-window buffer)))
        (when w
          (delete-window w)))
      (kill-buffer buffer))))

;; (defun pydbgr-reset-keymaps()
;;   "This unbinds the special debugger keys of the source buffers."
;;   (interactive)
;;   (setcdr (assq 'pydbgr-debugger-support-minor-mode minor-mode-map-alist)
;; 	  pydbgr-debugger-support-minor-mode-map-when-deactive))


(defun pydbgr-customize ()
  "Use `customize' to edit the settings of the `pydbgr' debugger."
  (interactive)
  (customize-group 'pydbgr))


;; -------------------------------------------------------------------
;; The end.
;;

;;; Local variables:
;;; eval:(put 'pydbgr-debug-enter 'lisp-indent-hook 1)
;;; End:

;;; pydbgr-core.el ends here