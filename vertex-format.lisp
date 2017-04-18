#|
 This file is a part of trial
 (c) 2016 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)
(in-readtable :qtools)

(defun vformat-write-vector (stream array &optional (type (array-element-type array)))
  (when (<= (expt 2 32) (length array))
    (error "Array is longer than 2³² elements."))
  (fast-io:write32-be (length array) stream)
  (ecase type
    ((:char)
     (fast-io:writeu8 0 stream)
     (loop for value across array
           do (fast-io:write8 value stream)))
    ((fixnum :int :fixnum)
     (fast-io:writeu8 1 stream)
     (loop for value across array
           do (fast-io:write64-be value stream)))
    ((single-float :float)
     (fast-io:writeu8 2 stream)
     (loop for value across array
           do (fast-io:writeu32-be (ieee-floats:encode-float32 value) stream)))
    ((double-float :double)
     (fast-io:writeu8 3 stream)
     (loop for value across array
           do (fast-io:writeu64-be (ieee-floats:encode-float64 value) stream)))))

(defun vformat-read-vector (stream)
  (let* ((size (fast-io:read32-be stream))
         (type (fast-io:readu8 stream))
         (array (cffi:foreign-alloc (ecase type
                                      (0 :char)
                                      (1 :int)
                                      (2 :float)
                                      (3 :double))
                                    :count size)))
    (values (ecase type
              (0 (loop for i from 0 below size
                       do (setf (cffi:mem-aref array :int i) (fast-io:read64-be stream))))
              (1 (loop for i from 0 below size
                       do (setf (cffi:mem-aref array :float i) (ieee-floats:decode-float32 (fast-io:readu32-be stream)))))
              (2 (loop for i from 0 below size
                       do (setf (cffi:mem-aref array :double i) (ieee-floats:decode-float64 (fast-io:readu64-be stream))))))
            size
            type)))

(defun vformat-write-string (stream string)
  (loop for char across string
        do (fast-io:writeu8 (char-code char) stream))
  (fast-io:writeu8 0 stream))

(defun vformat-read-string (stream)
  (let ((string (make-array 0 :element-type 'character :initial-element #\Null :adjustable T :fill-pointer T)))
    (loop for code = (fast-io:readu8 stream)
          until (= 0 code)
          do (vector-push-extend (code-char code) string))
    string))

(defun vertex-buffer-type->int (type)
  (position type *vertex-buffer-type-list*))

(defun int->vertex-buffer-type (int)
  (elt *vertex-buffer-type-list* int))

(defun vertex-buffer-usage->int (type)
  (position type *vertex-buffer-data-usage-list*))

(defun int->vertex-buffer-usage (int)
  (elt *vertex-buffer-data-usage-list* int))

(defun vformat-write-buffer (stream data type usage &optional (element-type (array-element-type data)))
  (vformat-write-string stream "VBUF")
  (fast-io:writeu8 (vertex-buffer-type->int type) stream)
  (fast-io:writeu8 (vertex-buffer-usage->int usage) stream)
  (vformat-write-vector stream data element-type))

(defun vformat-read-buffer (stream)
  (let ((name (vformat-read-string stream)))
    (unless (string= name "VBUF")
      (error "Expected vertex buffer identifier, but got ~s" name)))
  (let ((type (int->vertex-buffer-type (fast-io:readu8 stream)))
        (usage (int->vertex-buffer-usage (fast-io:readu8 stream))))
    (multiple-value-bind (data size element-type) (vformat-read-vector stream)
      (values data size type usage element-type))))

(defun vformat-write-array (stream buffer-refs)
  (when (<= (expt 2 8) (length buffer-refs))
    (error "More than 2⁸ buffer refs."))
  (vformat-write-string stream "VARR")
  (fast-io:writeu8 (length buffer-refs) stream)
  (loop for (buffers index size stride offset normalized) in buffer-refs
        do (fast-io:writeu8 (length buffers) stream)
           (dolist (buffer buffers)
             (fast-io:writeu8 buffer stream))
           (fast-io:writeu8 index stream)
           (fast-io:writeu8 size stream)
           (fast-io:writeu8 stride stream)
           (fast-io:writeu8 offset stream)
           (fast-io:writeu8 (if normalized 1 0) stream)))

(defun vformat-read-array (stream)
  (let ((name (vformat-read-string stream)))
    (unless (string= name "VARR")
      (error "Expected vertex array identifier, but got ~s" name)))
  (let ((size (fast-io:readu8 stream)))
    (loop repeat size
          collect (list (loop repeat (fast-io:readu8 stream)
                              collect (fast-io:readu8 stream))
                        (fast-io:readu8 stream)
                        (fast-io:readu8 stream)
                        (fast-io:readu8 stream)
                        (fast-io:readu8 stream)
                        (if (< 0 (fast-io:readu8 stream)) T NIL)))))

(defun vformat-write-bundle (stream buffers array)
  (when (<= (expt 2 8) (length buffers))
    (error "More than 2⁸ buffers."))
  (vformat-write-string stream "VBUN")
  (fast-io:writeu8 (length buffers) stream)
  (dolist (buffer buffers)
    (etypecase buffer
      (list (apply #'vformat-write-buffer stream buffer))
      (vertex-buffer-asset
       (vformat-write-buffer stream (first (inputs buffer))
                             (buffer-type buffer)
                             (data-usage buffer)
                             (element-type buffer)))))
  (etypecase array
    (list (apply #'vformat-write-array stream array))
    (vertex-array-asset
     (vformat-write-array
      stream (loop for i from 0
                   for input in (inputs array)
                   collect (destructuring-bind (buffers &key (index i)
                                                             (size 3)
                                                             (stride 0)
                                                             (offset 0)
                                                             (normalized NIL))
                               input
                             (list (loop for buffer in (enlist buffers)
                                         collect (position buffer buffers))
                                   index size stride offset normalized)))))))

(defun vformat-read-bundle (stream)
  (let ((name (vformat-read-string stream)))
    (unless (string= name "VBUN")
      (error "Expected vertex bundle identifier, but got ~s" name)))
  (let* ((buffers (loop repeat (fast-io:readu8 stream)
                        collect (multiple-value-bind (data size type usage element-type)
                                    (vformat-read-buffer stream)
                                  (let ((asset (make-asset 'vertex-array-asset
                                                           (list data)
                                                           :type type
                                                           :element-type element-type
                                                           :data-usage usage
                                                           :size size)))
                                    (prog1 (load asset)
                                      (setf (inputs asset) NIL)
                                      (cffi:foreign-free data))))))
         (inputs (loop for (buffers index size stride offset normalized) in (vformat-read-array stream)
                       collect (list (loop for buffer in buffers
                                           collect (elt buffers buffer))
                                     :index index
                                     :size size
                                     :stride stride
                                     :offset offset
                                     :normalized normalized))))
    (let ((asset (make-asset 'vertex-array-asset inputs)))
      (prog1 (load asset)
        (setf (inputs asset) NIL)
        (mapcar #'offload buffers)))))