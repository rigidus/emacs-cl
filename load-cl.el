(require 'cl)
(setq max-lisp-eval-depth 10000)
(setq max-specpdl-size 5000)

;;; Fake an IN-PACKAGE macro.
(defmacro IN-PACKAGE (name) nil)

(let ((load-path (cons "~/src/emacs-cl" load-path))
      (debug-on-error t))
  (load "utils")

  (load "cl-evaluation")
  (load "cl-flow")
  (load "cl-numbers")
  (load "cl-conses")
  (load "cl-arrays")
  (load "cl-sequences")
  (load "cl-structures")
  (load "cl-iteration")

  (load "cl-characters")
  (load "cl-strings")
  (load "cl-symbols")
  (load "cl-packages")

  (load "cl-types")
  (load "cl-typep")
  (load "cl-subtypep")

  (load "cl-hash")
  (load "cl-streams")
  (load "cl-reader")
  (load "cl-printer")
  (load "cl-environment")
  (load "cl-system")
  (load "interaction")
  (load "cl-eval")

  (load "populate"))

(IN-PACKAGE "CL-USER")
(populate-packages)
(garbage-collect)
