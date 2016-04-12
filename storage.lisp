#|
 This file is a part of trial
 (c) 2016 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)
(in-readtable :qtools)

(defvar *unpack-target*)
(defvar *pack-compile* T)

(defun save-to-stream (stream object)
  (write object :stream stream
                :array T
                :base 10
                :case :downcase
                :circle T
                :escape T
                :gensym T
                :pretty T
                :radix NIL
                :readably T))

(defun ins (class-name &rest args)
  (enter (apply #'make-instance class-name args) *unpack-target*))

(define-compiler-macro ins (class-name &rest args)
  `(enter (make-instance ,class-name ,@args) *unpack-target*))

(defclass savable ()
  ())

(defgeneric save (savable)
  (:method-combination append))

(defmethod save append (thing)
  ())

(defmethod save :around (thing)
  (when (typep thing 'savable)
    (call-next-method)))

(defmethod save :around ((savable savable))
  `(ins ',(class-name (class-of savable))
        ,@(call-next-method)))

(defgeneric pack (to &rest objects))

(defmethod pack ((to string) &rest objects)
  (apply #'pack (uiop:parse-native-namestring to) objects))

(defmethod pack ((to pathname) &rest objects)
  (let ((temp (make-pathname :name (format NIL "~a-~a"
                                           (pathname-name to) (get-universal-time))
                             :type "tmp.lisp" :defaults to)))
    (v:info :trial.storage "Packing to ~a ..." (uiop:native-namestring temp))
    (with-open-file (stream temp :direction :output
                                 :if-exists :rename
                                 :if-does-not-exist :create)
      (save-to-stream stream `(in-package '#:trial-user))
      (apply #'pack stream objects))
    (cond (*pack-compile*
           (v:info :trial.storage "Compiling to ~a ..." (uiop:native-namestring to))
           (unwind-protect
                (compile-file temp :output-file to)
             (ignore-errors (delete-file temp))))
          (T
           (rename-file temp to)))))

(defmethod pack ((to stream) &rest objects)
  (dolist (object objects)
    (save-to-stream to (save object))))

(defgeneric unpack (from into))

(defmethod unpack ((from string) into)
  (unpack (uiop:parse-native-namestring from) into))

(defmethod unpack ((from pathname) into)
  (let ((*unpack-target* into))
    (v:info :trial.storage "Unpacking ~a to ~a" (uiop:native-namestring from) into)
    (load from)))