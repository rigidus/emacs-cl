;;;; -*- emacs-lisp -*-
;;;
;;; Copyright (C) 2003 Lars Brinkhoff.
;;; This file implements operators in chapter 14, Conses.

(defun TERPRI ()
  (princ "\n"))

(defmacro* PRINT-UNREADABLE-OBJECT ((object stream &key identity) &body body)
  `(progn
    (princ "#<")
    (princ (TYPE-OF ,object))
    (princ " ")
    ,@body
    ,@(when identity
        `((princ " ")
	  (princ "identity")))
    (princ ">")))

(defun write-char-to-*standard-output* (char)
  (WRITE-CHAR (CODE-CHAR char) *STANDARD-OUTPUT*))

;;; Ad-hoc unexensible.
(defun PRIN1 (object &optional stream-designator)
  (let* ((stream (resolve-output-stream-designator stream-designator))
	 (*STANDARD-OUTPUT* stream)
	 (standard-output #'write-char-to-*standard-output*))
    (cond
      ((or (integerp object)
	   (floatp object))
       (princ object))
      ((symbolp object)
       (cond
	 ((eq (nth-value 0 (FIND-SYMBOL (SYMBOL-NAME object) *PACKAGE*))
	      object)
	  (princ (SYMBOL-NAME object)))
	 ((null (SYMBOL-PACKAGE object))
	  (princ "#:")
	  (princ (SYMBOL-NAME object)))
	 ((eq (SYMBOL-PACKAGE object) *keyword-package*)
	  (princ ":")
	  (princ (SYMBOL-NAME object)))
	 (t
	  (princ (PACKAGE-NAME (SYMBOL-PACKAGE object)))
	  (princ (if (eq (nth-value 1 (FIND-SYMBOL (SYMBOL-NAME object)
						   (SYMBOL-PACKAGE object)))
			 *:external*)
		     ":"
		     "::"))
	  (princ (SYMBOL-NAME object)))))
      ((CHARACTERP object)
       (princ "#\\")
       (princ (or (CHAR-NAME object)
		  (string (CHAR-CODE object)))))
      ((consp object)
       (princ "(")
       (PRINT (car object))
       (while (consp (cdr object))
	 (princ " ")
	 (setq object (cdr object))
	 (PRINT (car object)))
       (unless (null (cdr object))
	 (princ " . ")
	 (PRINT (cdr object)))
       (princ ")"))
      ((COMPILED-FUNCTION-P object)
       (PRINT-UNREADABLE-OBJECT (object stream :identity t)))
      ((INTERPRETED-FUNCTION-P object)
       (PRINT-UNREADABLE-OBJECT (object stream :identity t)))
      ((FUNCTIONP object)
       (PRINT-UNREADABLE-OBJECT (object stream :identity t)))
      ((cl::bignump object)
       (when (MINUSP object)
	 (princ "-")
	 (setq object (cl:- object)))
       (princ "#x")
       (let ((start t))
	 (dotimes (i (1- (length object)))
	   (let ((num (aref object (- (length object) i 1))))
	     (dotimes (j 7)
	       (let ((n (logand (ash num (* -4 (- 6 j))) 15)))
		 (unless (and (zerop n) start)
		   (setq start nil)
		   (princ (string (aref "0123456789ABCDEF" n))))))))))
      ((cl::ratiop object)
       (PRINT (NUMERATOR object))
       (princ "/")
       (PRINT (DENOMINATOR object)))
      ((COMPLEXP object)
       (princ "#C(")
       (PRINT (REALPART object))
       (princ " ")
       (PRINT (IMAGPART object))
       (princ ")"))
      ((BIT-VECTOR-P object)
       (princ "#*")
       (dotimes (i (LENGTH object))
	 (princ (AREF object i))))
      ((STRINGP object)
       (princ "\"")
       (dotimes (i (LENGTH object))
	 (let ((char (CHAR-CODE (CHAR object i))))
	   (case char
	     (34	(princ "\\\""))
	     (92	(princ "\\\\"))
	     (t		(princ (string char))))))
       (princ "\""))
      ((VECTORP object)
       (princ "#(")
       (dotimes (i (LENGTH object))
	 (PRINT (AREF object i))
	 (when (< (1+ i) (LENGTH object))
	   (princ " ")))
       (princ ")"))
      ((PACKAGEP object)
       (PRINT-UNREADABLE-OBJECT (object stream)
         (princ (PACKAGE-NAME object))))
      ((READTABLEP object)
       (PRINT-UNREADABLE-OBJECT (object stream :identity t)))
      ((STREAMP object)
       (PRINT-UNREADABLE-OBJECT (object stream :identity t)
         (cond
	   ((STREAM-filename object)
	    (princ object))
	   ((bufferp (STREAM-content object))
	    (princ (buffer-name (STREAM-content object))))
	   ((STRINGP (STREAM-content object))
	    (princ (string 34))
	    (princ (STREAM-content object))
	    (princ (string 34))))))
      (t
       (error))))
  object)

(defun PRINT (object &optional stream)
  (TERPRI)
  (PRIN1 object stream)
  (princ " "))

(defun FORMAT (stream-designator format &rest args)
  (let ((stream (or (and (eq stream-designator t) *STANDARD-OUTPUT*)
		    stream-designator
		    (MAKE-STRING-OUTPUT-STREAM)))
	(i 0))
    (while (< i (LENGTH format))
      (let ((char (CHAR format i)))
	(if (eq (CHAR-CODE char) 126)
	    (case (CHAR-CODE (CHAR format (incf i)))
	      (37	(TERPRI))
	      (65	(PRINT (pop args) stream))
	      (68	(PRINT (pop args) stream)))
	    (WRITE-CHAR char stream)))
      (incf i))
    (if stream-designator
	nil
	(GET-OUTPUT-STREAM-STRING stream))))

