#|
 This file is a part of trial
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)

(defvar *selection-color-counter* 0)

(defun ensure-selection-color (color)
  (etypecase color
    ((unsigned-byte 32) color)
    (vec4
     (let ((id 0))
       (setf (ldb (byte 8 0) id)  (floor (* 255 (vw color))))
       (setf (ldb (byte 8 8) id)  (floor (* 255 (vz color))))
       (setf (ldb (byte 8 16) id) (floor (* 255 (vy color))))
       (setf (ldb (byte 8 24) id) (floor (* 255 (vx color))))
       id))
    (cons
     (let ((id 0))
       (setf (ldb (byte 8 0) id) (fourth color))
       (setf (ldb (byte 8 8) id) (third color))
       (setf (ldb (byte 8 16) id) (second color))
       (setf (ldb (byte 8 24) id) (first color))
       id))
    ((vector integer 4)
     (let ((id 0))
       (setf (ldb (byte 8 0) id) (aref color 3))
       (setf (ldb (byte 8 8) id) (aref color 2))
       (setf (ldb (byte 8 16) id) (aref color 1))
       (setf (ldb (byte 8 24) id) (aref color 0))
       id))))

(defclass selection-buffer (render-texture bakable)
  ((scene :initarg :scene :accessor scene)
   (color->object-map :initform (make-hash-table :test 'eql) :accessor color->object-map))
  (:default-initargs
   :width (error "WIDTH required.")
   :height (error "HEIGHT required.")
   :scene (error "SCENE required.")))

(defmethod initialize-instance :after ((buffer selection-buffer) &key scene)
  (enter (make-instance 'selection-buffer-pass) buffer)
  (add-handler buffer scene))

(defmethod bake ((buffer selection-buffer))
  (pack buffer)
  (for:for ((object over (scene buffer)))
    (register-object-for-pass buffer object)))

(defmethod finalize :after ((buffer selection-buffer))
  (remove-handler buffer (scene buffer)))

(defmethod object-at-point ((point vec2) (buffer selection-buffer))
  (color->object (gl:read-pixels (round (vx point)) (round (vy point)) 1 1 :rgba :unsigned-byte)
                 buffer))

(defmethod color->object (color (buffer selection-buffer))
  (gethash (ensure-selection-color color)
           (color->object-map buffer)))

(defmethod (setf color->object) (object color (buffer selection-buffer))
  (if object
      (setf (gethash (ensure-selection-color color)
                     (color->object-map buffer))
            object)
      (remhash (ensure-selection-color color)
               (color->object-map buffer))))

(defmethod handle (thing (buffer selection-buffer)))

(defmethod handle ((resize resize) (buffer selection-buffer))
  (setf (width buffer) (width resize)
        (height buffer) (height resize))
  (resize buffer (width resize) (height resize)))

(defmethod handle ((enter enter) (buffer selection-buffer))
  (let ((entity (entity enter)))
    (when (typep entity 'selectable)
      (register-object-for-pass (aref (passes buffer) 0) entity))))

(defmethod handle ((leave leave) (buffer selection-buffer))
  (let ((entity (entity leave)))
    (when (typep entity 'selectable)
      (setf (color->object (selection-color entity) buffer) NIL))))

(defmethod paint ((source selection-buffer) (buffer selection-buffer))
  (paint-with buffer (scene source))
  (gl:bind-framebuffer :draw-framebuffer 0)
  (%gl:blit-framebuffer 0 0 (width source) (height source) 0 0 (width source) (height source)
                        (cffi:foreign-bitfield-value '%gl::ClearBufferMask :color-buffer)
                        (cffi:foreign-enum-value '%gl:enum :nearest)))

(defmethod paint-with :around ((buffer selection-buffer) thing)
  (with-pushed-attribs
    (disable :blend)
    (call-next-method)))

(define-shader-pass selection-buffer-pass (render-pass)
  ())

(define-class-shader (selection-buffer-pass :fragment-shader)
  "uniform vec4 selection_color;
out vec4 color;

void main(){
  color = selection_color;
}")

(define-shader-entity selectable ()
  ((selection-color :initarg :selection-color :initform (find-new-selection-color) :accessor selection-color)))

(defun find-new-selection-color ()
  (let ((num (incf *selection-color-counter*)))
    (vec4 (/ (ldb (byte 8 24) num) 255.0)
          (/ (ldb (byte 8 16) num) 255.0)
          (/ (ldb (byte 8 8) num) 255.0)
          (/ (ldb (byte 8 0) num) 255.0))))

(defmethod paint :around ((entity entity) (pass selection-buffer-pass))
  (when (or (typep entity 'selectable)
            (typep entity 'container))
    (call-next-method)))

(defmethod paint :before ((entity selectable) (pass selection-buffer-pass))
  (let ((shader (shader-program-for-pass pass entity)))
    (setf (uniform shader "selection_color") (selection-color entity))))

(defmethod register-object-for-pass :after ((buffer selection-buffer) (selectable selectable))
  (setf (color->object (selection-color selectable) buffer) selectable))

