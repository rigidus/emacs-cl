;;;; -*- emacs-lisp -*-
;;;
;;; Copyright (C) 2003 Lars Brinkhoff.
;;; This file implements operators in chapter 9, Conditions.

(defvar *condition-constructors* (make-hash-table))

(defmacro* DEFINE-CONDITION (name parents slots &rest options)
  (with-gensyms (constructor)
    `(progn
       (DEFSTRUCT (,name
		   (:copier nil)
		   (:constructor ,constructor)
		   ,@(when parents
		       `((:include ,(first parents)))))
	 ,@slots)
       (puthash ',name ',constructor *condition-constructors*)
       ',name)))

(DEFINE-CONDITION CONDITION () ())

(DEFINE-CONDITION WARNING (CONDITION) ())

(DEFINE-CONDITION STYLE-WARNING (WARNING) ())

(DEFINE-CONDITION SERIOUS-CONDITION (CONDITION) ())

(DEFINE-CONDITION ERROR (SERIOUS-CONDITION) ())

(DEFINE-CONDITION CELL-ERROR (ERROR) (NAME))

(DEFINE-CONDITION PARSE-ERROR (ERROR) ())

(DEFINE-CONDITION STORAGE-CONDITION (SERIOUS-CONDITION) ())

(cl:defmacro ASSERT (form &optional places datum &rest args)
  (with-gensyms (continue)
    `(DO ()
         (,form)
       (RESTART-BIND ((CONTINUE (LAMBDA () (GO ,continue))))
	 (ERROR ,@(if datum `(,datum ,@args) '((QUOTE ERROR)))))
       ,continue
       (PRINC "\nFix the error already!"))))

(defun condition (datum args default-type)
  (cond
    ((TYPEP datum 'CONDITION)
     datum)
    ((symbolp datum)
     (apply #'MAKE-CONDITION datum args))
    ((STRINGP datum)
     ;; TODO: (kw FORMAT-CONTROL) and (kw FORMAT-ARGUMENTS)
     (MAKE-CONDITION default-type :format datum :args args))
    (t
     (error "invalid condition designator"))))

(defun ERROR (datum &rest args)
  (let ((condition (condition datum args 'SIMPLE-ERROR)))
    (SIGNAL condition)
    (INVOKE-DEBUGGER condition)))

(defmacro* restart-bind (bindings &body forms)
  `(let ((*restart-alist*
	  (append (list ,@(mapcar (lambda (binding)
				    `(CONS ',(first binding)
				           ,(second binding)))
				  bindings))
		  *restart-alist*)))
     ,@forms))

(defun* CERROR (format datum &rest args)
  (restart-bind ((CONTINUE (lambda () (return-from CERROR))))
    (apply #'ERROR datum args)))

(cl:defmacro CHECK-TYPE (place type &optional string)
  `(UNLESS (TYPEP ,place ',type)
     ;; TODO...
     (ERROR 'TYPE-ERROR)))

;; TODO: inherit from SIMPLE-CONDITION
(DEFINE-CONDITION SIMPLE-ERROR (ERROR) (format args))

(defvar *condition-handler-alist* nil)

(defun SIGNAL (datum &rest args)
  (let ((condition (condition datum args 'SIMPLE-CONDITION)))
    (when (TYPEP condition *BREAK-ON-SIGNALS*)
      (INVOKE-DEBUGGER condition))
    (let ((handler (ASSOC condition *condition-handler-alist* :test #'TYPEP)))
      (when handler
	(FUNCALL (cdr handler) condition)))
    nil))

(DEFINE-CONDITION SIMPLE-CONDITION (CONDITION) (format args))

(defun SIMPLE-CONDITION-FORMAT-CONTROL (condition)
  (cond
    ((TYPEP condition 'SIMPLE-CONDITION) (SIMPLE-CONDITION-format condition))
    ((TYPEP condition 'SIMPLE-ERROR)     (SIMPLE-ERROR-format condition))
    ((TYPEP condition 'SIMPLE-WARNING)   (SIMPLE-WARNING-format condition))
    (t					 (error "this sucks"))))

(defun SIMPLE-CONDITION-FORMAT-ARGUMENTS (condition)
  (cond
    ((TYPEP condition 'SIMPLE-CONDITION) (SIMPLE-CONDITION-args condition))
    ((TYPEP condition 'SIMPLE-ERROR)     (SIMPLE-ERROR-args condition))
    ((TYPEP condition 'SIMPLE-WARNING)   (SIMPLE-WARNING-args condition))
    (t					 (error "this sucks"))))

(defun WARN (datum &rest args)
  (let ((condition (condition datum args 'SIMPLE-WARNING)))
    (SIGNAL condition)
    (PRINT condition *ERROR-OUTPUT*)
    nil))

;; TODO: inherit from SIMPLE-CONDITION
(DEFINE-CONDITION SIMPLE-WARNING (WARNING) (format args))

(defun INVOKE-DEBUGGER (condition)
  (let* ((hook *DEBUGGER-HOOK*)
	 (*DEBUGGER-HOOK* nil))
    (when hook
      (FUNCALL hook condition hook))
    (PRINC "\nDebugger invoked on condition of type ")
    (PRIN1 (TYPE-OF condition))
    (PRINC "\nAvailable restarts: ")
    (dolist (restart (COMPUTE-RESTARTS))
      (PRINT restart))
    (when (y-or-n-p "Restart? ")
      (INVOKE-RESTART (first (COMPUTE-RESTARTS))))
    (debug)))

(defun* BREAK (&optional format &rest args)
  (restart-bind ((CONTINUE (lambda () (return-from BREAK))))
    (debug)))

(defvar *DEBUGGER-HOOK* nil)

(defvar *BREAK-ON-SIGNALS* nil)

(defmacro* HANDLER-BIND (bindings &body body)
  `(let ((*condition-handler-alist*
	  (append (list ,@(mapcar (lambda (binding)
				    `(cons ',(first binding)
				           ,(second binding)))
				  bindings))
		  *condition-handler-alist*)))
     ,@body))

(cl:defmacro HANDLER-BIND (bindings &body body)
  `(LET ((*condition-handler-alist*
	  (APPEND (LIST ,@(mapcar (lambda (binding)
				    `(CONS (QUOTE ,(first binding))
				           ,(second binding)))
				  bindings))
		  *condition-handler-alist*)))
     ,@body))

;;; TODO: HANDLER-CASE

(cl:defmacro IGNORE-ERRORS (&rest forms)
  (with-gensyms (block)
    `(BLOCK ,block
       (HANDLER-BIND ((ERROR (LAMBDA (c) (RETURN-FROM ,block (VALUES nil c)))))
	 ,@forms))))

(defun MAKE-CONDITION (type &rest args)
  (let ((fn (gethash type *condition-constructors*)))
    (if fn
	(APPLY fn args)
	(error "no such condition type"))))

(DEFSTRUCT (RESTART
	     (:constructor make-restart (NAME handler &optional condition))
	     (:predicate restartp))
  NAME handler condition)

(defvar *restart-alist* nil)

(defun COMPUTE-RESTARTS (&optional condition)
  (mapcar (lambda (cons) (make-restart (car cons) (cdr cons)))
	  *restart-alist*))

(defun FIND-RESTART (restart &optional condition)
  ;; TODO: consider condition
  (cond
    ((restartp restart)		restart)
    ((null restart)		(error "TODO"))
    ((symbolp restart)		(let ((cons (assoc restart *restart-alist*)))
				  (when cons
				    (make-restart restart (cdr cons)))))
    (t				(ERROR 'TYPE-ERROR))))

(defun INVOKE-RESTART (restart-designator &rest args)
  (let ((restart (FIND-RESTART restart-designator)))
    (if restart
	(APPLY (RESTART-handler restart) args)
	(ERROR 'CONTROL-ERROR))))

;;; TODO: INVOKE-RESTART-INTERACTIVELY

(cl:defmacro RESTART-BIND (bindings &body forms)
  `(LET ((*restart-alist*
	  (APPEND (LIST ,@(mapcar (lambda (binding)
				    `(CONS (QUOTE ,(first binding))
				           ,(second binding)))
				  bindings))
		  *restart-alist*)))
     ,@forms))

;;; TODO: RESTART-CASE

;;; RESTART-NAME defined by defstruct.

;;; TODO: WITH-CONDITION-RESTARTS

;;; TODO:
; (cl:defmacro WITH-SIMPLE-RESTART ((name format &rest args)
; 				  &body body)
;   `(RESTART-CASE (PROGN ,@body)
;      (,name ()
;        :report (LAMBDA (stream) (FORMAT stream ,format ,@args))
;        (VALUES nil T))))

(defun ABORT (&optional condition)
  (INVOKE-RESTART 'ABORT))

(defun CONTINUE (&optional condition)
  (let ((restart (FIND-RESTART 'CONTINUE)))
    (when restart
      (INVOKE-RESTART restart))))

(defun MUFFLE-WARNING (&optional condition)
  (INVOKE-RESTART 'MUFFLE-WARNING))

(defun STORE-VALUE (value &optional condition)
  (let ((restart (FIND-RESTART 'STORE-VALUE)))
    (when restart
      (INVOKE-RESTART restart value))))

(defun USE-VALUE (value &optional condition)
  (let ((restart (FIND-RESTART 'USE-VALUE)))
    (when restart
      (INVOKE-RESTART restart value))))


(DEFINE-CONDITION TYPE-ERROR (ERROR) (DATUM EXPECTED-TYPE))
(DEFINE-CONDITION CONTROL-ERROR (ERROR) ())
(DEFINE-CONDITION UNBOUND-VARIABLE (CELL-ERROR) ())
(DEFINE-CONDITION UNDEFINED-FUNCTION (CELL-ERROR) ())
(DEFINE-CONDITION PACKAGE-ERROR (ERROR) (PACKAGE))