;;;; -*- emacs-lisp -*-
;;;
;;; Copyright (C) 2003 Lars Brinkhoff.
;;; This file implements operators in chapter 13, Characters.

(IN-PACKAGE "EMACS-CL")

(defun CHARACTER (x)
  (cond
    ((CHARACTERP x)			x)
    ((and (STRINGP x) (= (LENGTH x) 1))	(AREF x 0))
    ((SYMBOLP x)			(CHARACTER (SYMBOL-NAME x)))
    (t
     (error "invalid character designator"))))

(defun CHARACTERP (char)
  (vector-and-typep char 'character))

(defun ALPHA-CHAR-P (char)
  (or (cl:<= 65 (CHAR-CODE char) 90)
      (cl:<= 97 (CHAR-CODE char) 122)))

(defun ALPHANUMERICP (char)
  (or (DIGIT-CHAR-P char) (ALPHA-CHAR-P char)))

(defun* DIGIT-CHAR (weight &optional (radix 10))
  (when (cl:< weight radix)
    (CODE-CHAR (if (< weight 10)
		   (+ 48 weight)
		   (+ 65 weight -10)))))

(defun* DIGIT-CHAR-P (char &optional (radix 10))
  (let* ((code (CHAR-CODE char))
	 (n (cond
	      ((cl:<= 48 code 57) (- code 48))
	      ((cl:<= 65 code 90) (- code 65 -10))
	      ((cl:<= 95 code 122) (- code 95 -10))
	      (t 99))))
    (if (< n radix) n nil)))

(DEFCONSTANT CHAR-CODE-LIMIT 256)

(defun CODE-CHAR (code)
  (if (and (integerp code) (< code CHAR-CODE-LIMIT))
      (vector 'character code)
      nil))

(defun CHAR-CODE (char)
  ;;(CHECK-TYPE char 'character)
  (aref char 1))

(defun CHAR= (&rest chars)
  (apply #'cl:= (mapcar #'CHAR-CODE chars)))

(defun CHAR/= (&rest chars)
  (apply #'cl:/= (mapcar #'CHAR-CODE chars)))

(defun CHAR< (&rest chars)
  (apply #'cl:< (mapcar #'CHAR-CODE chars)))

(defun CHAR> (&rest chars)
  (apply #'cl:> (mapcar #'CHAR-CODE chars)))

(defun CHAR<= (&rest chars)
  (apply #'cl:<= (mapcar #'CHAR-CODE chars)))

(defun CHAR>= (&rest chars)
  (apply #'cl:>= (mapcar #'CHAR-CODE chars)))

(defun char-downcase-code (char)
  (CHAR-CODE (CHAR-DOWNCASE char)))

(defun CHAR-EQUAL (&rest chars)
  (apply #'cl:= (mapcar #'char-downcase-code chars)))

(defun CHAR-NOT-EQUAL (&rest chars)
  (apply #'cl:/= (mapcar #'char-downcase-code chars)))

(defun CHAR-LESSP (&rest chars)
  (apply #'cl:< (mapcar #'char-downcase-code chars)))

(defun CHAR-GREATERP (&rest chars)
  (apply #'cl:> (mapcar #'char-downcase-code chars)))

(defun CHAR-NOT-GREATERP (&rest chars)
  (apply #'cl:<= (mapcar #'char-downcase-code chars)))

(defun CHAR-NOT-LESSP (&rest chars)
  (apply #'cl:>= (mapcar #'char-downcase-code chars)))

(defun CHAR-UPCASE (char)
  (if (LOWER-CASE-P char)
      (CODE-CHAR (- (CHAR-CODE char) 32))
      char))

(defun CHAR-DOWNCASE (char)
  (if (UPPER-CASE-P char)
      (CODE-CHAR (+ (CHAR-CODE char) 32))
      char))

(defun LOWER-CASE-P (char)
  ;;(CHECK-TYPE char 'character)
  (cl:<= 97 (CHAR-CODE char) 122))

(defun UPPER-CASE-P (char)
  ;;(CHECK-TYPE char 'character)
  (cl:<= 65 (CHAR-CODE char) 90))

(defun NAME-CHAR (name)
  (let ((string (STRING name)))
    (cond
      ((equalp string "Backspace")	(CODE-CHAR 8))
      ((equalp string "Tab")		(CODE-CHAR 9))
      ((equalp string "Newline")	(CODE-CHAR 10))
      ((equalp string "Linefeed")	(CODE-CHAR 10))
      ((equalp string "Page")		(CODE-CHAR 12))
      ((equalp string "Return")		(CODE-CHAR 13))
      ((equalp string "Space")		(CODE-CHAR 32))
      ((equalp string "Rubout")		(CODE-CHAR 127)))))

(defun CHAR-NAME (char)
  (case (CHAR-CODE char)
    (8		"Backspace")
    (9		"Tab")
    (10		"Newline")
    (12		"Page")
    (13		"Return")
    (32		"Space")
    (127	"Rubout")))
