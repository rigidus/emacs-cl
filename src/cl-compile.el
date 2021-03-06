;;;; -*- emacs-lisp -*-
;;;
;;; Copyright (C) 2003, 2004 Lars Brinkhoff.
;;; This file implements the compiler.

(IN-PACKAGE "EMACS-CL")

;;; TODO: `(QUOTE ,foo) -> `(LOAD-TIME-VALUE ,(MAKE-LOAD-FORM foo) T)

;;; (defun fac (n) (if (< n 2) 1 (* n (fac (1- n)))))
;;; (fac 100)
;;; 0.31 seconds

;;; (defun fib (n) (if (< n 2) 1 (+ (fib (1- n)) (fib (- n 2)))))
;;; (fib 22)
;;; 2.223 seconds

;;; (defun tak (x y z)
;;;   (if (not (< y x))
;;;       z
;;;       (tak (tak (1- x) y z) (tak (1- y) z x) (tak (1- z) x y))))
;;; (tak 18 12 6)
;;; 1.134 seconds

(defun COMPILE (name &optional definition)
  (when (null definition)
    (setq definition (if (FBOUNDP name)
			 (FDEFINITION name)
			 (MACRO-FUNCTION name))))
  (when (INTERPRETED-FUNCTION-P definition)
    (setq definition (FUNCTION-LAMBDA-EXPRESSION definition)))
  (when (consp definition)
    (setq definition (compile1 definition)))
  (if name
      (progn
	(if (FBOUNDP name)
	    (setf (FDEFINITION name) definition)
	    (setf (MACRO-FUNCTION name) definition))
	(cl:values name nil nil))
      (cl:values definition nil nil)))

; .elc header for GNU Emacs 20.7:
;ELC   
;;; Compiled by lars@nocrew.org on Sun Mar 21 10:33:13 2004
;;; from file /home/lars/src/emacs-cl/func.el
;;; in Emacs version 20.7.2
;;; with bytecomp version 2.56
;;; with all optimizations.

; .elc header for GNU Emacs 21.3:
;ELC   
;;; Compiled by lars@nocrew.org on Sun Mar 21 10:01:44 2004
;;; from file /home/lars/src/emacs-cl/func.el
;;; in Emacs version 21.3.1
;;; with bytecomp version 2.85.4.1
;;; with all optimizations.

; .elc header for XEmacs 21.4:
;ELC   
;;; compiled by lars@nocrew.org on Sun Mar 21 10:29:35 2004
;;; from file /home/lars/src/emacs-cl/func.el
;;; emacs version 21.4 (patch 6) "Common Lisp" XEmacs Lucid.
;;; bytecomp version 2.27 XEmacs; 2000-09-12.
;;; optimization is on.
;;; this file uses opcodes which do not exist in Emacs 19.

(cond
  ((eval-when-compile (eq (type-of (make-hash-table)) 'hash-table))
   (defmacro make-literal-table ()
     `(make-hash-table :test ',(if (featurep 'xemacs) 'equal 'EQUAL)))
   (defmacro get-literal (literal)
     `(gethash ,literal *compile-file-literals*))
   (defmacro put-literal (literal symbol)
     `(puthash ,literal ,symbol *compile-file-literals*))
   (defmacro remove-literal (literal)
     `(remhash ,literal *compile-file-literals*)))
  (t
   (defmacro make-literal-table ()
     `(list nil))
   (defmacro get-literal (literal)
     `(cdr (assq ,literal *compile-file-literals*)))
   (defmacro put-literal (literal symbol)
     `(push (cons ,literal ,symbol) *compile-file-literals*))
   (defmacro remove-literal (literal)
     `(setq *compile-file-literals*
            (assq-delete-all ,literal *compile-file-literals*)))))

(unless (fboundp 'assq-delete-all)
  (defun assq-delete-all (key alist)
    (delete* key alist :test 'eq :key 'car)))

(cl:defun COMPILE-FILE (input-file
			&REST keys
			&KEY OUTPUT-FILE
			     (VERBOSE *COMPILE-VERBOSE*)
			     (PRINT *COMPILE-PRINT*)
			     EXTERNAL-FORMAT)
  (let* ((*PACKAGE* *PACKAGE*)
	 (*READTABLE* *READTABLE*)
	 (*COMPILE-FILE-PATHNAME* (MERGE-PATHNAMES input-file))
	 (*COMPILE-FILE-TRUENAME* (TRUENAME *COMPILE-FILE-PATHNAME*))
	 (output (apply #'COMPILE-FILE-PATHNAME input-file keys))
	 (warnings-p nil)
	 (failure-p nil)
	 (*compile-file-mode* :not-compile-time)
	 (*compile-file-literals* (make-literal-table)))
    (WITH-COMPILATION-UNIT ()
      (let ((coding-system-for-read 'no-conversion)
	    (coding-system-for-write 'no-conversion))
	(WITH-OPEN-FILE (in *COMPILE-FILE-PATHNAME*)
	  (when VERBOSE
	    (FORMAT T "~&;Compiling ~A~%"
		    (NAMESTRING *COMPILE-FILE-PATHNAME*)))
	  (WITH-OPEN-FILE (out "/tmp/temp.el" (kw DIRECTION) (kw OUTPUT))
	    (let ((eof (gensym)))
	      (do ((form (READ in nil eof) (READ in nil eof)))
		  ((eq form eof))
		(when PRINT
		  (FORMAT T "~&;  ~S~%" (if (consp form)
					    (car form)
					    form)))
		(let* ((*compile-file-forms* nil)
		       (compiled-form (compile2 form)))
		  (dolist (form (nreverse *compile-file-forms*))
		    (WRITE-LINE (prin1-to-string form) out))
		  (WRITE-LINE (prin1-to-string compiled-form) out))))))
	(if (byte-compile-file "/tmp/temp.el")
	    (rename-file "/tmp/temp.elc" (NAMESTRING output) t)
	    (setq failure-p t))))
    (delete-file "/tmp/temp.el")
    (cl:values (TRUENAME output) warnings-p failure-p)))



(defvar *compile-file-mode* nil
  "Indicates whether file compilation is in effect, and if so, which
   mode: :compile-time-too, :not-compile-time, or t (neither of the
   previous two, but still compiling a file).")

(defvar *compile-file-literals* nil
  "A table for literals found by COMPILE-FILE.")

(defvar *compile-file-forms*)

(defvar *genreg-counter* 0)

(defun genreg ()
  (prog1 (make-symbol (format "R%d" *genreg-counter*))
    (incf *genreg-counter*)))

(defvar *registers* (list (genreg)))
(defvar *next-register* nil)

(defvar *bound* nil
  "A list of variables bound in the function currently being compiled.")

(defvar *free* nil
  "An alist of all variables are ever free in any function in the
   top-level form being compiled.")

(defvar *blocks-mentioned* nil
  "A list of all block names mentioned in the top-level form being compiled.")

(defun new-register ()
  (prog1
      (car *next-register*)
    (when (null (cdr *next-register*))
      (setf (cdr *next-register*) (list (genreg))))
    (setf *next-register* (cdr *next-register*))))

(defun lambda-expr-p (form)
  (and (consp form)
       (eq (car form) 'LAMBDA)))

(defmacro* with-fresh-context (&body body)
  `(let ((*next-register* *registers*)
	 (*free* nil)
	 (*bound* nil)
	 (*blocks-mentioned* nil))
     ,@body))

(defun compile1 (form)
  (byte-compile (compile2 form)))

(defun compile2 (form)
  (with-fresh-context
    (compile-form form *global-environment*)))

(defun cl-compiler-macroexpand (form name env)
  (let* ((fn (COMPILER-MACRO-FUNCTION name))
	 (new (if fn (FUNCALL *MACROEXPAND-HOOK* fn form env) form)))
    (when (and (not (eq form new))
	       (consp form))
      (setq form (cl-compiler-macroexpand
		  new
		  (if (eq (first new) 'FUNCALL)
		      (second new)
		      (first new))
		  env)))
    form))

(defconst +toplevel-forms+
  '(PROGN LOCALLY MACROLET SYMBOL-MACROLET EVAL-WHEN))

(defun* compile-form (form &optional env &key (values 1))
  (unless env
    (setq env *global-environment*))
  (when (and (consp form) (symbolp (first form)))
    (let* ((name (first form))
	   (fn (gethash name *form-compilers*)))
      (when fn
	(let ((*compile-file-mode*
	       (if (memq name +toplevel-forms+)
		   *compile-file-mode*
		   (when *compile-file-mode* t))))
	  (return-from compile-form (apply fn env (rest form)))))))
  (setq form (cl:values (MACROEXPAND form env)))
  (cond
    ((and (symbolp form) (not (KEYWORDP form)))
     (unless (eq values 0)
       (let ((val (compile-variable form env)))
	 (if (eq values t)
	     (if (null val)
		 `(setq nvals 1 mvals nil)
		 `(progn (setq nvals 1 mvals nil) ,val))
	     val))))
    ((atom form)
     (unless (eq values 0)
       (let ((val (compile-literal form env)))
	 (if (eq values t)
	     (if (null val)
		 `(setq nvals 1 mvals nil)
		 `(progn (setq nvals 1 mvals nil) ,val))
	     val))))
    ((lambda-expr-p (first form))
     (let* ((lexp (first form))
	    (vars (cadr lexp))
	    (body (cddr lexp))
	    (args (rest form))
	    (*compile-file-mode* (when *compile-file-mode* t)))
     (if (and (every #'symbolp vars)
	      (notany #'lambda-list-keyword-p vars)
	      (eq (length vars) (length args)))
	 (compile-form `(LET ,(MAPCAR #'list vars args) ,@body) env)
	 `(,(compile-lambda vars body env t) ,@(compile-forms args env)))))
    ((symbolp (first form))
     (let* ((name (first form))
	    (fn (gethash name *form-compilers*)))
       (if fn
	   (let ((*compile-file-mode*
		  (if (memq name +toplevel-forms+)
		      *compile-file-mode*
		      (when *compile-file-mode* t))))
	     (apply fn env (rest form)))
	   (let ((*compile-file-mode* (when *compile-file-mode* t)))
	     (compile-funcall `(FUNCTION ,name) (rest form) env)))))
    (t
     (ERROR "Syntax error: ~S" form))))

(defun compile-forms (args env)
  (mapcar (lambda (arg) (compile-form arg env)) args))

(defun* compile-body (forms env &key (values t))
  (if (null forms)
      nil
      (do* ((forms forms (cdr forms))
	    (form (car forms) (car forms))
	    (result nil))
	   ((null (cdr forms))
	    (push (compile-form form env :values values) result)
	    (nreverse result))
	(let ((comp (compile-form form env :values 0)))
	  (when comp
	    (push comp result))))))

(defun compile-variable (var env)
  (multiple-value-bind (type localp decls) (variable-information var env)
    (ecase type
      ((:special nil)	(if *compile-file-mode*
			    (if (interned-p var)
				var
				`(symbol-value ,(compile-literal var env)))
			    var))
      (:lexical		(when (and (not (memq var *bound*))
				   (not (MEMBER var *free* (kw KEY) #'car)))
			  (push (cons var (lexical-value var env)) *free*))
			(lexical-value var env))
      (:constant	(compile-literal (symbol-value var) env)))))

(defvar *literal-counter* 0)

(defun compile-load-time-value (form env &optional read-only-p)
  (if *compile-file-mode*
      (let ((symbol (intern (format "--emacs-cl-load-time--%d"
				    (incf *literal-counter*)))))
	(push `(setq ,symbol ,(compile-form form nil)) *compile-file-forms*)
	symbol)
      `(quote ,(eval-with-env form nil))))

(defun compile-literal (literal env)
  (cond
    ((null literal)
     nil)
    (*compile-file-mode*
     (or (and (symbolp literal)
	      (interned-p literal)
	      `(quote ,literal))
	 (get-literal literal)
	 (make-file-literal literal env)))
    ((or (consp literal) (symbolp literal))
     `(quote ,literal))
    (t
     literal)))

(defun make-file-literal (literal env)
  (let ((symbol (intern (format "--emacs-cl-literal--%d"
				(incf *literal-counter*)))))
    (put-literal literal symbol)
    (MULTIPLE-VALUE-BIND (load-form init-form) (MAKE-LOAD-FORM literal env)
      (cond
	((eq load-form literal)
	 (remove-literal literal)
	 literal)
	(t
	 (push `(setq ,symbol ,(compile-form load-form env))
	       *compile-file-forms*)
	 (push (compile-form init-form env) *compile-file-forms*)
	 symbol)))))

(defun built-in-make-load-form (form &optional env)
  (cl:values nil)
  (cond
    ((null form)
     nil)
    ((or (NUMBERP form) (CHARACTERP form) (SIMPLE-VECTOR-P form)  (subrp form)
	 (stringp form) (bit-vector-p form) (byte-code-function-p form))
     form)
    ((symbolp form)
     (cond
       ((SYMBOL-PACKAGE form)
	`(INTERN ,(SYMBOL-NAME form) ,(PACKAGE-NAME (SYMBOL-PACKAGE form))))
       (t
	`(MAKE-SYMBOL ,(SYMBOL-NAME form)))))
    ((PACKAGEP form)
     `(FIND-PACKAGE ,(PACKAGE-NAME form)))
    ;; TODO: RANDOM-STATE
    ((consp form)
     (if (and (ok-for-file-literal-p (car form))
	      (ok-for-file-literal-p (cdr form)))
	 (cl:values `(cons ,(car form) ,(cdr form)))
	 (cl:values
	  `(cons nil nil)
	  `(LET ((form (QUOTE ,form)))
	    (setcar form (QUOTE ,(car form)))
	    (setcdr form (QUOTE ,(cdr form)))))))
;;     ((and (bit-vector-p form)
;; 	  (not (featurep 'xemacs)))
;;      ;; There's a bug in GNU Emacs (20.7 and 21.3).  Bit vectors
;;      ;; printed to a source file and then byte-compiled can make the
;;      ;; compiled file unloadable due to error in the #& syntax.
;;	;; RESOLVED: Bind coding-system-for-write and coding-system-for-read
;;	;; to 'no-conversion.
;;      `(READ-FROM-STRING ,(PRIN1-TO-STRING form)))
    ((VECTORP form)
     (COPY-SEQ form))
    ((ARRAYP form)
     ;; Just dump the raw vector.
     form)
    ((HASH-TABLE-P form)
     `(LET ((table (MAKE-HASH-TABLE ,(kw TEST)
				    (QUOTE ,(HASH-TABLE-TEST form)))))
        (DOLIST (cons (QUOTE
		       ,(let ((result nil))
			  (MAPHASH (lambda (k v) (push (cons k v) result))
				   form)
			  result)))
	  (SETF (GETHASH (CAR cons) table) (CDR cons)))
       table))
    ((PATHNAMEP form)
     ;; Just dump the raw vector.
     form)
    ((and (INTERPRETED-FUNCTION-P form)
	  (eq (interp-fn-env form) *global-environment*))
     (byte-compile (compile-form (interp-fn-lambda-exp form))))
    (t
     (ERROR "~S is not an exteralizable object." form))))

(defun ok-for-file-literal-p (object)
  (or (stringp object)
      (null object)))
;;    (and (symbolp object)
;; 	   (interned-p object))))

(defvar *form-compilers* (make-hash-table))

(defmacro* define-compiler (operator lambda-list env &body body)
  `(setf (gethash (if (stringp ',operator)
		      (INTERN ,operator *emacs-cl-package*)
		      ',operator)
		  *form-compilers*)
	 (function* (lambda (,env ,@lambda-list) ,@body))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define-compiler "*" (&rest args) env
  (case (length args)
    (0	1)
    (1	(compile-form (first args) env))
    (2	`(binary* ,@(compile-forms args env)))
    (t	(compile-funcall `(QUOTE ,(INTERN "*" *cl-package*)) args env))))

(define-compiler "+" (&rest args) env
  (case (length args)
    (0	0)
    (1	(compile-form (first args) env))
    (2	`(binary+ ,@(compile-forms args env)))
    (t	(compile-funcall `(QUOTE ,(INTERN "+" *cl-package*)) args env))))

(define-compiler "1+" (arg) env
  `(prog1 (binary+ ,(compile-form arg env) 1)
     (setq nvals 1 mvals nil)))

(define-compiler "1-" (arg) env
  `(binary+ ,(compile-form arg env) -1))

(define-compiler "=" (&rest args) env
  (case (length args)
    (0	(ERROR "'=' needs at least one argument"))
    (1	'T)
    (2	`(binary= ,@(compile-forms args env)))
    (t	(compile-funcall `(QUOTE ,(INTERN "=" *cl-package*)) args env))))

(define-compiler "/=" (&rest args) env
  (case (length args)
    (0	(ERROR "'/=' needs at least one argument"))
    (1	'T)
    (2	`(not (binary= ,@(compile-forms args env))))
    (t	(compile-funcall `(QUOTE ,(INTERN "/=" *cl-package*)) args env))))

(define-compiler "<" (&rest args) env
  (case (length args)
    (0	(ERROR "'<' needs at least one argument"))
    (1	'T)
    (2	`(binary< ,@(compile-forms args env)))
    (t	(compile-funcall `(QUOTE ,(INTERN "<" *cl-package*)) args env))))

(define-compiler "<=" (&rest args) env
  (case (length args)
    (0	(ERROR "'<=' needs at least one argument"))
    (1	'T)
    (2	`(binary<= ,@(compile-forms args env)))
    (t	(compile-funcall `(QUOTE ,(INTERN "<=" *cl-package*)) args env))))

(define-compiler ">" (&rest args) env
  (case (length args)
    (0	(ERROR "'>' needs at least one argument"))
    (1	'T)
    (2	(let ((forms (compile-forms args env)))
	  `(binary< ,(second forms) ,(first forms))))
    (t	(compile-funcall `(QUOTE ,(INTERN ">" *cl-package*)) args env))))

(define-compiler ">=" (&rest args) env
  (case (length args)
    (0	(ERROR "'>=' needs at least one argument"))
    (1	'T)
    (2	(let ((forms (compile-forms args env)))
	  `(binary<= ,(second forms) ,(first forms))))
    (t	(compile-funcall `(QUOTE ,(INTERN ">=" *cl-package*)) args env))))

(define-compiler APPLY (fn &rest args) env
  (if (zerop (length args))
      (ERROR 'PROGRAM-ERROR)
      (let ((fn (compile-form fn env))
	    (args (compile-forms args env)))
	(cond
	  ((subrp fn)
	   `(apply #',(intern (function-name fn)) ,@args))
	  ((byte-code-function-p fn)
	   `(apply ,fn ,@args))
	  (t
	   `(APPLY ,fn ,@args))))))

(define-compiler BLOCK (tag &rest body) env
  (let* ((block (gensym))
	 (new-env (augment-environment env :block (cons tag block)))
	 (compiled-body (compile-body body new-env)))
    (if (memq block *blocks-mentioned*)
	`(catch ',block ,@compiled-body)
	(body-form compiled-body))))

(define-compiler CATCH (tag &rest body) env
  `(catch ,(compile-form tag env) ,@(compile-body body env)))

(define-compiler COMPLEMENT (fn) env
  (setq fn (MACROEXPAND fn env))
  (if (and (consp fn)
	   (eq (first fn) 'FUNCTION))
      (if (lambda-expr-p (second fn))
	  (let ((args (cadadr fn))
		(body (cddadr fn)))
	    (compile-form `(LAMBDA ,args (not (PROGN ,@body))) env))
	  (with-gensyms (args)
	    `(lambda (&rest ,args)
	       (not (APPLY ,(compile-form fn env) ,args)))))
      `(COMPLEMENT ,(compile-form fn env))))

(define-compiler COND (&rest clauses) env
  `(cond
     ,@(mapcar (destructuring-lambda ((&whole clause condition &rest forms))
	         (if (and (CONSTANTP condition)
			  (not (null condition)))
		     `(t ,@(compile-body forms env))
		     (mapcar (lambda (form) (compile-form form env))
			     clause)))
	       clauses)))

(define-compiler EVAL-WHEN (situations &rest body) env
  (cond
    ((or (eq *compile-file-mode* :compile-time-too)
	 (eq *compile-file-mode* :not-compile-time))
     (compile-file-eval-when situations body env))
    ((or (memq (kw EXECUTE) situations)
	 (memq 'EVAL situations))
     (body-form (compile-body body env)))))

(defun compile-file-eval-when (situations body env)
  (let* ((ex (or (memq (kw EXECUTE) situations)
		 (memq 'EVAL situations)))
	 (ct (or (memq (kw COMPILE-TOPLEVEL) situations)
		 (memq 'COMPILE situations)))
	 (lt (or (memq (kw LOAD-TOPLEVEL) situations)
		 (memq 'LOAD situations)))
	 (ctt (eq *compile-file-mode* :compile-time-too))
	 (nct (eq *compile-file-mode* :not-compile-time)))
    ;; Figure 3-7 from CLHS:
    ;;   CT   LT   EX   Mode  Action    New Mode
    ;;   -----------------------------------------------
    ;; 1 Yes  Yes  ---  ---   Process   compile-time-too
    ;; 2 No   Yes  Yes  CTT   Process   compile-time-too
    ;; 3 No   Yes  Yes  NCT   Process   not-compile-time
    ;; 4 No   Yes  No   ---   Process   not-compile-time
    ;; 5 Yes  No   ---  ---   Evaluate  ---
    ;; 6 No   No   Yes  CTT   Evaluate  ---
    ;; 7 No   No   Yes  NCT   Discard   ---
    ;; 8 No   No   No   ---   Discard   ---
    (cond
      ((or (and ct lt)				;1
	   (and (not ct) lt ex ctt))		;2
       (eval-with-env `(PROGN ,@body) env)
       (let ((*compile-file-mode* :compile-time-too))
	 (body-form (compile-body body env))))
      ((or (and (not ct) lt ex nct)		;3
	   (and (not ct) lt (not ex)))		;4
       (let ((*compile-file-mode* :not-compile-time))
	 (body-form (compile-body body env))))
      ((or (and ct (not lt))			;5
	   (and (not ct) (not lt) ex ctt))	;6
       (let* ((*compile-file-mode* t)
	      (result (eval-with-env `(PROGN ,@body) env)))
	 (unless (eq values 0)
	   (compile-literal result env))))
      ((or (and (not ct) (not lt) ex nct)	;7
	   (and (not ct) (not lt) (not ex)))	;8
       nil)
      (t
       (ERROR "Bug here.")))))

(define-compiler FLET (fns &rest forms) env
  (MULTIPLE-VALUE-BIND (body decls) (parse-body forms)
    (let ((new-env (augment-environment env :function (mapcar #'first fns)))
	  (bindings nil))
      (dolist (fn fns)
	(destructuring-bind (name lambda-list &rest forms) fn
	  (let ((reg (new-register)))
	    (setf (lexical-function name new-env) reg)
	    (MULTIPLE-VALUE-BIND (body decls doc) (parse-body forms t)
	      (push `(,reg ,(compile-lambda
			     lambda-list
			     `((BLOCK ,(function-block-name name) ,@body))
			     env))
		    bindings)))))
      (let ((compiled-body (compile-body body new-env)))
	(cond
	  ((null *free*))
	  ((create-environment-p env new-env)
	   (setq compiled-body (compile-environment compiled-body new-env)))
	  (t
	   (setq compiled-body
		 (compile-env-inits compiled-body
				    (mapcar
				     (lambda (fn)
				       (lexical-function (car fn) new-env))
				     fns)
				    new-env))))
	`(let ,bindings ,@compiled-body)))))

(defun constant-function-name-p (object)
  (and (consp object)
       (memq (first object) '(QUOTE FUNCTION))
       (or (symbolp (second object))
	   (setf-name-p (second object)))))

(defun compile-funcall (fn args env)
  (let ((compiled-args (compile-forms args env)))
    (unless (null compiled-args)
      (let ((last (last compiled-args)))
	(unless (or (atom (car last))
		    (eq (first (car last)) 'quote))
	  (setf (car last)
		`(prog1 ,(car last) (setq nvals 1 mvals nil))))))
    (if (constant-function-name-p fn)
	(let ((name (second fn)))
	  (multiple-value-bind (type localp decls)
	      (function-information name (unless (eq (first fn) 'QUOTE) env))
	    (cond
	      ((eq name 'FUNCALL)
	       (when (null args)
		 (ERROR 'PROGRAM-ERROR))
	       (compile-funcall (first args) (rest args) env))
	      (localp
	       (when (and (not (memq name *bound*))
			  (not (MEMBER name *free* (kw KEY) #'car)))
		 (push (cons name (lexical-function name env))
		       *free*))
	       `(funcall ,(lexical-function name env) ,@compiled-args))
	      ((and (symbolp name)
		    (fboundp name)
		    (subrp (symbol-function name)))
	       `(,(intern (function-name (symbol-function name)))
		 ,@compiled-args))
	      ((interned-p name)
	       `(,name ,@compiled-args))
	      ((COMPILER-MACRO-FUNCTION name env)
	       (compile-form (cl-compiler-macroexpand form name env) env))
	      ((and (symbolp name) (not *compile-file-mode*))
	       `(,name ,@compiled-args))
	      (t
	       `(FUNCALL ,(compile-literal name env) ,@compiled-args)))))
	(let ((fn (compile-form fn env)))
	  (cond
	    ((subrp fn)
	     `(,(intern (function-name fn)) ,@compiled-args))
	    ((byte-code-function-p fn)
	     `(funcall ,fn ,@compiled-args))
	    (t
	     `(FUNCALL ,fn ,@compiled-args)))))))

(define-compiler FUNCALL (fn &rest args) env
  (compile-funcall fn args env))

(defun known-function-p (name)
  (and (symbolp name)
       (eq (SYMBOL-PACKAGE name) *emacs-cl-package*)))

(define-compiler FUNCTION (name) env
  (if (lambda-expr-p name)
      (compile-lambda (cadr name) (cddr name) env)
      (multiple-value-bind (type localp decl) (function-information name env)
	(cond
	  (localp	(when (and (not (memq name *bound*))
				   (not (MEMBER name *free*
						(kw KEY) #'car)))
			  (push (cons name (lexical-function name env))
				*free*))
			(lexical-function name env))
	  ((or (symbolp name) (setf-name-p name))
			(if (known-function-p name)
			    (compile-load-time-value
			     `(FDEFINITION (QUOTE ,name)) env)
			    `(FDEFINITION ,(compile-literal name env))))
	  (t		(ERROR "Syntax error: (FUNCTION ~S)" name))))))

(define-compiler GO (tag) env
  (let ((info (tagbody-information tag env)))
    (if info
	`(throw ',info ',tag)
	(ERROR "No tagbody for (GO ~S)" tag))))

(define-compiler IF (condition then &optional else) env
  (let ((compiled-condition (compile-form condition env))
	(compiled-then (compile-form then env)))
    (cond
      ((null compiled-condition)
       (compile-form else env))
      ((CONSTANTP condition env)
       compiled-then)
      ((equal compiled-condition compiled-then)
       `(or ,compiled-condition
	    ,@(when else
		(list (compile-form else env)))))
      (t
       `(if ,compiled-condition
	    ,compiled-then
	    ,@(when else
	        (list (compile-form else env))))))))

(define-compiler LABELS (fns &rest forms) env
  (MULTIPLE-VALUE-BIND (body decls) (parse-body forms)
    (let ((new-env (augment-environment env :function (mapcar #'first fns)))
	  (bindings nil)
	  (inits nil))
      (dolist (fn fns)
	(let ((reg (new-register)))
	  (setf (lexical-function (first fn) new-env) reg)
	  (push reg bindings)))
      (dolist (fn fns)
	(destructuring-bind (name lambda-list &rest forms) fn
	  (MULTIPLE-VALUE-BIND (body decls doc) (parse-body forms t)
	    (setq inits `(,(lexical-function name new-env)
			  ,(compile-lambda
			    lambda-list
			    `((BLOCK ,(function-block-name name) ,@body))
			    new-env)
			  ,@inits)))))
      (let ((compiled-body (compile-body body new-env)))
	(cond
	  ((null *free*))
	  ((create-environment-p env new-env)
	   (setq compiled-body (compile-environment compiled-body new-env)))
	  (t
	   (setq compiled-body
		 (compile-env-inits compiled-body
				    (mapcar
				     (lambda (fn)
				       (lexical-function (car fn) new-env))
				     fns)
				    new-env))))
	`(let ,bindings (setf ,@inits) ,@compiled-body)))))

(if (fboundp 'compiled-function-constants)
    (progn
      (defconst compiled-function-accessors
	'(compiled-function-arglist compiled-function-instructions
	  compiled-function-constants compiled-function-stack-depth
	  compiled-function-doc-string compiled-function-interactive))
      (defun cfref (fn i)
	(funcall (nth i compiled-function-accessors) fn)))
    (defun cfref (fn i)
      (aref fn i)))

(let ((fn (vector))
      (env (vector)))
  (defvar *trampoline-template*
    (byte-compile `(lambda (&rest args) (let ((env ,env)) (apply ,fn args)))))
  (defvar *trampoline-constants*
    (cfref *trampoline-template* 2))
  (defvar *trampoline-fn-pos*
    (position fn *trampoline-constants*))
  (defvar *trampoline-env-pos*
    (position env *trampoline-constants*)))

(defvar *trampoline-length*
  (condition-case c
      (length *trampoline-template*)
    (error 6)))

(defmacro defun-make-closure ()
  `(defun make-closure (fn env)
     (let* ((consts (copy-sequence ,*trampoline-constants*))
	    (tramp
	     (make-byte-code
	      ,@(let ((args nil))
		  (dotimes (i *trampoline-length* (nreverse args))
		    (push (if (eq i 2)
			      'consts
			      `',(cfref *trampoline-template* i))
			  args))))))
       (aset consts *trampoline-fn-pos* fn)
       (aset consts *trampoline-env-pos* env)
       tramp)))

(defun-make-closure)

(defun env-with-vars (env vars decls)
  (if vars
      (let ((new-env (augment-environment env :variable vars :declare decls)))
	(dolist (var vars)
	  (when (lexical-variable-p var new-env)
	    (setf (lexical-value var new-env) (new-register))
	    (push var *bound*)))
	new-env)
      env))

(defun variable-bound-p (var env)
  (nth-value 0 (variable-information var env)))

(defun create-environment-p (env new-env)
  (let ((vars (mapcar #'car *free*)))
    (and (every (lambda (var) (not (variable-bound-p var env))) vars)
	 (some (lambda (var) (variable-bound-p var new-env)) vars))))

(defun initial-environment (env)
  (mapcar (lambda (var)
	    (when (variable-bound-p (car var) env)
	      (cdr var)))
	  *free*))

(defun compile-environment (body env)
  (let ((inits (initial-environment env))
	(nfree (length *free*))
	make-env)
    (cond
      ((<= nfree 2)
       (setq make-env (if (eq nfree 1) `(cons ,@inits nil) `(cons ,@inits)))
       (MAPC (lambda (var accessor)
	       (setq body (NSUBST `(,accessor env) (cdr var) body)))
	     *free* '(car cdr)))
      (t
       (setq make-env `(vector ,@inits))
       (let ((i -1))
	 (dolist (var *free*)
	   (setq body (NSUBST `(aref env ,(incf i)) (cdr var) body))))))
    (prog1 `((let ((env ,make-env)) ,@body))
      (setq *free* nil))))

(defun compile-env-inits (body vars env)
  (let ((inits nil))
    (dolist (var *free*)
      (when (memq (cdr var) vars)
	    ;(and (memq (car var) vars)
	    ;	 (eq (compile-variable (car var) env) (cdr var)))
	(let ((reg (new-register)))
	  (setq inits `(,reg ,(cdr var) ,@inits))
	  (setq body (NSUBST reg (cdr var) body))
	  (setf (cdr var) reg))))
    (if inits
	`((setf ,@inits) ,@body)
	body)))

(defun compile-closure (lambda-list body env)
  `(make-closure ,(expand-lambda
		   lambda-list
		   (compile-env-inits body (compile-forms lambda-list env) env)
		   env)
		 env))

(defun compile-lambda (lambda-list forms env &optional keep-bindings)
  (MULTIPLE-VALUE-BIND (body decls doc) (parse-body forms t)
    (let* ((vars (lambda-list-variables lambda-list))
	   (*bound* (when keep-bindings *bound*))
	   (new-env (env-with-vars env vars decls))
	   (compiled-body (compile-body body new-env)))
      (dolist (decl decls)
	(when (eq (first decl) 'INTERACTIVE)
	  (push `(interactive ,@(rest decl)) compiled-body)))
      (when doc
	(when (null compiled-body)
	  (push nil compiled-body))
	(push doc compiled-body))
      (cond
	((null *free*)
	 (expand-lambda lambda-list compiled-body new-env))
	((create-environment-p env new-env)
	 (expand-lambda
	  lambda-list (compile-environment compiled-body new-env) new-env))
	(t
	 (compile-closure lambda-list compiled-body new-env))))))

(defun partition-bindings (bindings env)
  (let ((lexical-bindings nil)
	(special-bindings nil))
    (dolist (binding bindings)
      (let ((list (if (symbolp binding)
		      (list binding nil)
		      binding)))
	(if (lexical-variable-p (first list) env)
	    (push list lexical-bindings)
	    (push list special-bindings))))
    (cl:values lexical-bindings special-bindings)))

(defun first-or-identity (x)
  (if (atom x) x (car x)))

(defun body-form (body)
  (cond
    ((null body)				nil)
    ((and (consp body) (null (cdr body)))	(car body))
    (t						`(progn ,@body))))

(defun side-effect-free-p (form)
  (or (atom form)
      (let ((fn (car form)))
	(or (eq fn 'quote)
	    (and (symbolp fn)
		 (get fn 'side-effect-free)
		 (every #'side-effect-free-p (cdr form)))))))

(define-compiler LET (bindings &rest forms) env
  (MULTIPLE-VALUE-BIND (body decls) (parse-body forms)
    (let* ((vars (mapcar #'first-or-identity bindings))
	   (new-env (env-with-vars env vars decls))
	   (compiled-body (compile-body body new-env))
	   (special-bindings nil)
	   (let-bindings
	    (mapcan (lambda (binding)
		      (multiple-value-bind (var val save)
			  (if (consp binding)
			      (values (first binding) (second binding))
			      (values binding nil))
			(cond
			  ((and *compile-file-mode*
				(special-variable-p var new-env))
			   (let ((old (new-register))
				 (new (new-register)))
			     (setq var (compile-variable var new-env))
			     (push (list var old new) special-bindings)
			     (setq save `((,old ,var)))
			     (setq var new)))
			  (t
			   (setq var (compile-variable var new-env))))
			`(,@save (,var ,(compile-form val env)))))
		    bindings))
	   (body (cond
		   ((null *free*)
		    compiled-body)
		   ((create-environment-p env new-env)
		    (compile-environment compiled-body new-env))
		   (t
		    (compile-env-inits
		     compiled-body
		     (compile-forms (remove-if-not
				     (lambda (var)
				       (lexical-variable-p var new-env))
				     vars)
				    new-env)
		     new-env)))))
      (dolist (var vars)
	(when (lexical-variable-p var new-env)
	  (let* ((reg (compile-variable var new-env))
		 (list (find-if (lambda (list) (eq (first list) reg))
				let-bindings)))
	    (when nil ;(side-effect-free-p (second list))
	      (case (tree-count (first list) body)
		(0 (setq let-bindings (delq list let-bindings)))
		(1 (setq body (NSUBST (second list) (first list) body))
		   (setq let-bindings (delq list let-bindings))))))))
      (when special-bindings
	(setq body
	      `((unwind-protect
		    (progn
		      ,@(mapcar (destructuring-lambda ((var old new))
				  `(setf ,var ,new))
				special-bindings)
		      ,@body)
		  ,@(mapcar (destructuring-lambda ((var old new))
			      `(setf ,var ,old))
			    special-bindings)))))
      (if let-bindings
	  `(let ,let-bindings ,@body)
	  (body-form body)))))

(define-compiler LET* (bindings &rest forms) env
  (MULTIPLE-VALUE-BIND (body decls) (parse-body forms)
    (compile-form (if (null bindings)
		      `(LOCALLY ,@body)
		      `(LET (,(first bindings))
			(LET* ,(rest bindings)
			  ,@body)))
		  env)))

(define-compiler LOAD-TIME-VALUE (form &optional read-only-p) env
  (compile-load-time-value form env read-only-p))

(define-compiler LOCALLY (&rest forms) env
  (MULTIPLE-VALUE-BIND (body decls) (parse-body forms)
    ;; TODO: process decls
    (body-form (compile-body body env))))

(define-compiler MACROLET (macros &body forms) env
  (MULTIPLE-VALUE-BIND (body decls) (parse-body forms)
    (let ((new-env (env-with-macros env macros decls)))
      (body-form (compile-body body new-env)))))

(define-compiler MULTIPLE-VALUE-BIND (vars form &body forms) env
  (MULTIPLE-VALUE-BIND (body decls) (parse-body forms)
    (let* ((new-env (env-with-vars env vars decls))
	   (compiled-body (compile-body body new-env)))
      (unless (null *free*)
	(setq compiled-body
	      (if (create-environment-p env new-env)
		  (compile-environment compiled-body new-env)
		  (compile-env-inits compiled-body
				     (compile-forms vars new-env)
				     new-env))))
      (case (length vars)
	(0 `(progn
	     ,(compile-form form env :values 0)
	     ,@compiled-body))
	(1 `(let ((,(compile-variable (first vars) new-env)
		   ,(compile-form form env :values 1)))
	     ,@compiled-body))
	(t `(let* ((,(compile-variable (first vars) new-env)
		    ,(compile-form form env :values t))
		   ,@(mapcar (lambda (var)
			       `(,(compile-variable var new-env)
				 (pop mvals)))
			     (rest vars)))
	     ,@compiled-body))))))

(define-compiler MULTIPLE-VALUE-CALL (fn &rest forms) env
  (if (null forms)
      (compile-form `(FUNCALL ,fn) env)
      `(APPLY ,(compile-form fn env)
	      (append ,@(mapcar (lambda (form)
				  (compile-form
				   `(MULTIPLE-VALUE-LIST ,form)
				   env :values t))
				forms)))))

(define-compiler MULTIPLE-VALUE-LIST (form) env
  (let ((val (new-register)))
    `(let ((,val ,(compile-form form env :values t)))
       (if (zerop nvals)
	   nil
	   (cons ,val mvals)))))

(define-compiler MULTIPLE-VALUE-PROG1 (form &rest forms) env
  (let ((val (new-register))
	(ntemp (new-register))
	(mtemp (new-register)))
    `(let* ((,val ,(compile-form form env :values t))
	    (,ntemp nvals)
	    (,mtemp mvals))
       ,@(compile-body forms env :values 0)
       (setq nvals ,ntemp mvals ,mtemp)
       ,val)))

(define-compiler NOT (form) env
  `(if ,(compile-form form env) nil 'T))

(define-compiler NULL (form) env
  `(if ,(compile-form form env) nil 'T))

(define-compiler PROGN (&rest body) env
  (body-form (compile-body body env)))

(define-compiler PROGV (symbols values &body body) env
  `(do-progv ,(compile-form symbols env)
             ,(compile-form values env)
	     ,(compile-lambda () body env)))

(define-compiler QUOTE (form) env
  (compile-literal form env))

(define-compiler RETURN-FROM (tag &optional form) env
  (let ((block (block-information tag env)))
    (if block
	(let ((block-tag (cdr block)))
	  (pushnew block-tag *blocks-mentioned*)
	  `(throw ',block-tag ,(compile-form form env)))
	(ERROR "No block for (RETURN-FROM ~S)" form))))

(define-compiler SETQ (&rest forms) env
  (when (oddp (length forms))
    (ERROR "Odd number of forms in SETQ"))
  (body-form
   (mapcar2
    (lambda (var val)
      (unless (symbolp var)
	(ERROR "Setting non-symbol ~S." var))
      (multiple-value-bind (type localp) (variable-information var env)
	(ecase type
	  (:lexical
	   `(setf ,(compile-variable var env) ,(compile-form val env)))
	  ((:special nil)
	   (when (null type)
	     (WARN "Setting undefined variable ~S." var))
	   (if (and *compile-file-mode*
		    (not (interned-p var)))
	       `(set ,(compile-literal var env) ,(compile-form val env))
	       `(setq ,var ,(compile-form val env))))
	  (:symbol-macro
	   (compile-form `(SETF ,(MACROEXPAND var env) ,val) env))
	  (:constant
	   (ERROR "Setting constant ~S." var)))))
    forms)))

(define-compiler SYMBOL-MACROLET (macros &rest forms) env
  (MULTIPLE-VALUE-BIND (body decls) (parse-body forms)
    (let ((new-env (augment-environment env :symbol-macro
					(mapcar #'first macros))))
      (dolist (macro macros)
	(setf (lexical-value (first macro) new-env)
	      (enclose `(LAMBDA (form env) (QUOTE ,(second macro)))
		       env (first macro))))
      (body-form (compile-body body new-env)))))

(defun compile-tagbody-forms (forms tagbody start env)
  (let* ((nofirst (eq start (car forms)))
	 (clause (unless nofirst (list (list start)))))
    (do ((clauses nil)
	 (forms forms (cdr forms)))
	((null forms)
	 (unless (eq (first (car (last clause))) 'throw)
	   (setq clause (append clause `((throw ',tagbody nil)))))
	 (setq clauses (append clauses `(,clause)))
	 clauses)
      (let ((form (first forms)))
	(cond
	  ((atom form)
	   (unless nofirst
	     (setq clause (append clause `((throw ',tagbody ',form))))
	     (setq nofirst nil))
	   (when clause
	     (setq clauses (append clauses `(,clause))))
	   (setq clause `((,form))))
	  (t
	   (setq clause (append clause `(,(compile-form form env))))))))))

(define-compiler TAGBODY (&rest forms) env
  (let* ((tagbody (gensym))
	 (new-env (augment-environment
		   env :tagbody
		   (cons tagbody (remove-if-not #'go-tag-p forms))))
	 (pc (new-register))
	 (start (if (go-tag-p (car forms)) (car forms) (gensym))))
    (let ((last (last forms)))
      (cond
	((notany #'go-tag-p forms)
	 `(progn ,@forms nil))
	((and (consp last)
	      (setq last (car last))
	      (consp last)
	      (eq (first last) 'GO)
	      (eq (second last) start)
	      (notany #'go-tag-p (rest forms)))
	 `(while t ,@(compile-body (butlast (rest forms)) env :values 0)))
	(t
	 `(let ((,pc ',start))
	    (while (setq ,pc (catch ',tagbody
			       (case ,pc
				 ,@(compile-tagbody-forms
				    forms tagbody start new-env)))))))))))

(define-compiler THE (type form) env
  (compile-form form env))

(define-compiler THROW (tag form) env
  `(throw ,(compile-form tag env) ,(compile-form form env)))

(define-compiler UNWIND-PROTECT (protected &rest cleanups) env
  (let ((ntmp (new-register))
	(mtmp (new-register)))
    `(let (,ntmp ,mtmp)
       (prog1 (unwind-protect (prog1 ,(compile-form protected env)
				(setq ,ntmp nvals ,mtmp mvals))
		,@(compile-body cleanups env :values 0))
	 (setq nvals ,ntmp mvals ,mtmp)))))

(define-compiler VALUES (&rest forms) env
  (let ((n (length forms)))
    (case n
      (0	`(setq nvals 0 mvals nil))
      (1	`(prog1 ,(compile-form (car forms) env)
		   (setq nvals 1 mvals nil)))
      (t	`(prog1 ,(compile-form (car forms) env)
		   (setq nvals ,n
		         mvals (list ,@(compile-forms (cdr forms) env))))))))
