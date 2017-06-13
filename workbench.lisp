(in-package #:trial)

(define-pool workbench
  :base 'trial)

(define-asset (workbench cat) texture
    (#p"cat.png"))

(define-asset (workbench teapot) vertex-format
    (#p"teapot.vf"))

(define-shader-subject teapot (vertex-subject textured-subject located-entity rotated-entity)
  ()
  (:default-initargs
   :vertex-array (asset 'workbench 'teapot)
   :texture (asset 'workbench 'cat)))

(define-handler (teapot tick) (ev)
  (incf (vz (rotation teapot)) 0.02)
  (incf (vx (rotation teapot)) 0.01)
  (incf (vy (rotation teapot)) 0.03)
  (decf (vz (location teapot)) 0.1)
  (when (<= (vz (location teapot)) -20)
    (setf (vz (location teapot)) (random 10))))

(progn
  (defmethod setup-scene ((main main))
    (let ((scene (scene main)))
      (dotimes (i 100)
        (enter (make-instance 'teapot :location (vec3-random -10 10) :rotation (vec3-random -1 1)) scene))
      (enter (make-instance 'target-camera :location (vec 0 2 8)) scene)))

  (maybe-reload-scene))

(progn
  (defmethod setup-pipeline ((main main))
    (let ((pipeline (pipeline main))
          (pass1 (make-instance 'render-pass))
          (pass2 (make-instance 'negative-pass))
          (pass3 (make-instance 'box-blur-pass)))
      (connect (flow:port pass1 'color) (flow:port pass2 'previous-pass) pipeline)
      (connect (flow:port pass2 'color) (flow:port pass3 'previous-pass) pipeline)))

  (maybe-reload-scene))
