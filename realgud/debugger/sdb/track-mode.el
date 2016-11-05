;;; track-mode.el ---

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

;; sdb tracking a comint or eshell buffer.

(require 'load-relative)
(require-relative-list '(
                         "../../common/cmds"
                         "../../common/menu"
                         "../../common/track"
                         "../../common/track-mode"
                         )
                       "realgud-")
(require-relative-list '("core" "init") "realgud:sdb-")

(realgud-track-mode-vars "realgud:sdb")

(declare-function realgud-track-mode         'realgud-track-mode)
(declare-function realgud:track-mode-hook    'realgud-track-mode)
(declare-function realgud:track-mode-enable  'realgud-track-mode)
(declare-function realgud-track-mode-setup   'realgud-track-mode)
(declare-function realgud:track-set-debugger 'realgud-track-mode)

(define-key realgud:sdb-track-mode-map
  (kbd "C-c !b") 'realgud:goto-debugger-backtrace-line)

(defun realgud:sdb-track-mode-hook()
  (use-local-map realgud:sdb-track-mode-map)
  (realgud-track-mode-setup 't)
  (message "realgud:sdb track-mode-hook called")
)

(define-minor-mode realgud:sdb-track-mode
  "Minor mode for tracking sdb inside a process shell via realgud.

If called interactively with no prefix argument, the mode is toggled. A prefix argument, captured as ARG, enables the mode if the argument is positive, and disables it otherwise.

Key bindings:
\\{realgud:sdb-track-mode-map}
"
  :init-value nil
  ;; :lighter " sdb"   ;; mode-line indicator from realgud-track is sufficient.
  ;; The minor mode bindings.
  :global nil
  :group 'realgud:sdb
  :keymap realgud:sdb-track-mode-map
  (if realgud:sdb-track-mode
      (progn
        (realgud:track-set-debugger "sdb")
        (realgud:sdb-track-mode-hook)
        (realgud:track-mode-enable))
    (progn
      (setq realgud-track-mode nil)
      ))
)

(provide-me "realgud:sdb-")
;;; track-mode.el ends here
