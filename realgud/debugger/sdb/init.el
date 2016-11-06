;; Copyright (C) 2015-2016 Free Software Foundation, Inc

;; Author: Rocky Bernstein <rocky@gnu.org>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; sdb debugger

(eval-when-compile (require 'cl-lib))

(require 'load-relative)
(require-relative-list '("../../common/regexp" "../../common/loc") "realgud-")

(defvar realgud-pat-hash)
(declare-function make-realgud-loc-pat (realgud-loc))

(defvar realgud:sdb-pat-hash (make-hash-table :test 'equal)
  "hash key is the what kind of pattern we want to match:
backtrace, prompt, etc.  the values of a hash entry is a
realgud-loc-pat struct")

(declare-function make-realgud-loc "realgud-loc" (a b c d e f))

(defconst realgud:sdb-frame-file-regexp
  (format "\\(.+\\):%s" realgud:regexp-captured-num))

;; Regular expression that describes a lldb location generally shown
;; before a command prompt. NOTE: we assume annotate 1!
;; For example:
;; /src/build/ruby-2.1.5/main.c:24:454:beg:0x55555557659f
(setf (gethash "loc" realgud:sdb-pat-hash)
      (make-realgud-loc-pat
       :regexp (format "^%s:%s:beg:0x\\([0-9a-f]+\\)"
                       realgud:sdb-frame-file-regexp realgud:regexp-captured-num)
       :file-group 1
       :line-group 2
       :char-offset-group 3))

;; Regular expression that describes a sdb prompt
;; For example:
;;   (sdb)
(setf (gethash "prompt" realgud:sdb-pat-hash)
      (make-realgud-loc-pat
       :regexp   "^(sdb) "))

;; Regular expression that describes a "breakpoint set" line
;; For example:
;;   Breakpoint '0' added at '/home/k/tmp/gud/Main.fs:8'
(setf (gethash "brkpt-set" realgud:sdb-pat-hash)
      (make-realgud-loc-pat
       :regexp (format "^Breakpoint '%s' added at '\\(.+\\):%s'"
                       realgud:regexp-captured-num
                       realgud:regexp-captured-num)
       :num 1
       :file-group 3
       :line-group 4))

;; Regular expression that describes a debugger "delete" (breakpoint)
;; response.
;; For example:
;;   Deleted breakpoint 1
;;   Deleted breakpoints 1 2 3 4
(setf (gethash "brkpt-del" realgud:sdb-pat-hash)
      (make-realgud-loc-pat
       :regexp "^Breakpoint '\\([0-9]+\\)' deleted\n"
       :num 1))

(defconst realgud:sdb-frame-start-regexp
  "\\(?:^\\|\n\\)")

(defconst realgud:sdb-frame-num-regexp
  (format "#%s " realgud:regexp-captured-num))

;; Regular expression that describes a sdb "backtrace" command line.
;; For example:
;; #0  main (argc=2, argv=0xbffff564, envp=0xbffff570) at main.c:935
;; #1  0xb7e9f4a5 in *__GI___strdup (s=0xbffff760 "/tmp/remake/remake") at strdup.c:42
;; #2  0x080593ac in main (argc=2, argv=0xbffff5a4, envp=0xbffff5b0)
;;    at main.c:952
;; #46 0xb7f51b87 in vm_call_cfunc (th=0x804d188, reg_cfp=0xb7ba9e88, num=0,
;;    recv=157798080, blockptr=0x0, me=0x80d12a0) at vm_insnhelper.c:410

(setf (gethash "debugger-backtrace" realgud:sdb-pat-hash)
      (make-realgud-loc-pat
       :regexp          (concat realgud:sdb-frame-start-regexp
                        realgud:sdb-frame-num-regexp
                        "\\(?:.\\|\\(?:[\n] \\)\\)+[ ]+at "
                        realgud:sdb-frame-file-regexp
                        )
       :num 1
       :file-group 2
       :line-group 3)
      )

(setf (gethash "font-lock-keywords" realgud:sdb-pat-hash)
      '(
        ;; #2  0x080593ac in main (argc=2, argv=0xbffff5a4, envp=0xbffff5b0)
        ;;    at main.c:952
        ("[ \n]+at \\(.*\\):\\([0-9]+\\)"
         (1 realgud-file-name-face)
         (2 realgud-line-number-face))

        ;; The frame number and first type name, if present.
        ;; E.g. =>#0  Makefile.in at /tmp/Makefile:216
        ;;      ---^
        ( "#\\(?:^\\|\n\\)\\([0-9]+\\)  "
         (1 realgud-backtrace-number-face))
        ))

(setf (gethash "sdb" realgud-pat-hash) realgud:sdb-pat-hash)

;;  Prefix used in variable names (e.g. short-key-mode-map) for
;; this debugger

(setf (gethash "sdb" realgud:variable-basename-hash) "realgud:sdb")

(defvar realgud:sdb-command-hash (make-hash-table :test 'equal)
  "Hash key is command name like 'continue' and the value is
  the sdb command to use, like 'continue'")

(setf (gethash "break"    realgud:sdb-command-hash) "break %X:%l")
(setf (gethash "clear"    realgud:sdb-command-hash) "clear %X:%l")
(setf (gethash "continue" realgud:sdb-command-hash) "continue")
(setf (gethash "eval"     realgud:sdb-command-hash) "print %s")
(setf (gethash "quit"     realgud:sdb-command-hash) "quit")
(setf (gethash "run"      realgud:sdb-command-hash) "run")
(setf (gethash "step"     realgud:sdb-command-hash) "step %p")
(setf (gethash "sdb" realgud-command-hash) realgud:sdb-command-hash)

(setf (gethash "sdb" realgud-pat-hash) realgud:sdb-pat-hash)

(provide-me "realgud:sdb-")
