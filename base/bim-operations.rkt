#lang typed/racket/base/no-check
(require typed/racket/unit)
(require "coord.rkt")
(require "shapes.rkt")
(require "bim-families.rkt")
(provide (all-from-out "bim-families.rkt"))
(provide bim-ops^
         bim-ops@
         bim-extra-ops^
         bim-extra-ops@
         bim-ops-dependencies^
         bim-levels^
         bim-levels@
         bim-levels-dependencies^
         (struct-out level))

(define-signature bim-ops-dependencies^
  ([line : (->)]
   [surface-circle : (->)]
   [right-cuboid : (->)]
   [cuboid : (->)]
   [irregular-prism : (->)]
   [create-layer : (-> String Any)]
   [shape-layer : (->)]
   [box : (->)]
   [extrusion : (->)]
   [subtraction : (->)]
   [thicken : (->)]))

(struct level
  ([height : Real])
  #:type-name Level)

(define-signature bim-levels-dependencies^
  ([level : (->)]))

(define-signature bim-levels^
  ([current-level : (->)]
   [default-level-to-level-height : (ParameterOf Real)]
   [upper-level : (->)]))
   
(define-unit bim-levels@
  (import bim-levels-dependencies^)
  (export bim-levels^)

  (define current-level (make-parameter (level 0)))
  
  (define default-level-to-level-height (make-parameter 3))
  
  (define (upper-level [lvl : Level (current-level)]
                       [height : Real (default-level-to-level-height)])
    (level (+ (level-height lvl) height)))
  )
  

(define-signature bim-ops^
  ([polygonal-mass : (->)]
   [bim-family-layer : (->)]
   [beam : (->)]
   [column : (->)]
   [slab : (->)]
   [slab-path : (->)]
   [slab-opening-path : (->)]
   [roof : (->)]
   [wall : (->)]
   [walls : (->)]
   [door : (->)]
   [panel : (->)]))

(define-unit bim-ops@
  (import bim-ops-dependencies^ bim-levels^)
  (export bim-ops^)
  
(def-shape/no-provide (polygonal-mass [pts : Locs] [height : Real])
  (irregular-prism pts height))

  
(define (bim-family-layer [bim-family : BIM-Family])
  (or (unbox (bim-family-layer-ref bim-family))
      (let ((layer (create-layer (bim-family-layer-name bim-family))))
        (set-box! (bim-family-layer-ref bim-family) layer)
        layer)))

(define (vertical? p0 p1)
  (< (cyl-rho (p-p p0 p1)) 1e-10))

(def-shape/no-provide (beam [p0 : Loc] [p1 : Loc] [angle : Real 0] [family : Beam-Family (default-beam-family)])
  (let ((h (beam-family-height family))
        (w (beam-family-width family)))
    (let ((s (if (vertical? p0 p1)
                 (right-cuboid p0 w h p1 angle)
                 (let-values ([(cb dz) (position-and-height p0 p1)])
                   (right-cuboid (loc-in-world (+y cb (/ h -2)))
                                 (beam-family-width family) h
                                 (loc-in-world (+yz cb (/ h -2) dz))
                                 angle)))))
      (shape-layer s (bim-family-layer family))
      (shape-reference s))))

(def-shape/no-provide (column [center : Loc]
                   [bottom-level : Level (current-level)]
                   [top-level : Level (upper-level bottom-level)]
                   [family : Column-Family (default-column-family)])
  (let ((width (column-family-width family)))
    (let ((s (box (+xyz center (/ width -2) (/ width -2) (level-height bottom-level))
                  width
                  width
                  (- (level-height top-level) (level-height bottom-level)))))
      (shape-layer s (bim-family-layer family))
      (shape-reference s))))

(def-shape/no-provide (slab [vertices : Locs] [level : Level (current-level)] [family : Slab-Family (default-slab-family)])
  (let ((s (irregular-prism
            (map (lambda ([p : Loc])
                   (+z p (+ (level-height level)
                            (- (slab-family-thickness family))
                            (slab-family-coating-thickness family))))
                 vertices)
            (slab-family-thickness family))))
    (shape-layer s (bim-family-layer family))
    (shape-reference s)))

(def-shape/no-provide (slab-path [path : Any] [level : Level (current-level)] [family : Slab-Family (default-slab-family)])
  (let loop ((p path))
    (if (null? p)
        (list)
        (let ((e (car p)))
          (unless (null? (cdr p)) (error "Unfinished"))
          (cond ((line? e)
                 (error "Unfinished"))
                ((arc? e)
                 (error "Unfinished"))
                ((circle? e)
                 (let ((s
                        (extrusion
                         (surface-circle (+z (+z (circle-center e) (- (cz (circle-center e))))
                                             (level-height level))
                                         (circle-radius e))
                         (vz (- (slab-family-coating-thickness family)
                                (slab-family-thickness family))))))
                   (shape-layer s (bim-family-layer family))
                   (shape-reference s)))
                (else
                 (error "Unknown path component" e)))))))


(def-shape/no-provide (slab-opening-path [slab : Any] [path : Any])
  (let ((layer (shape-layer slab)))
    (let ((s
           (subtraction
            slab
            (slab-path path (slab-path-level slab) (slab-path-family slab)))))
      (shape-layer s layer)
      (shape-reference s))))

        
(def-shape/no-provide (roof [vertices : Locs] [level : Level (current-level)] [family : Roof-Family (default-roof-family)])
  (let ((s (irregular-prism
            (map (lambda ([p : Loc])
                   (+z p (+ (level-height level)
                            (- (roof-family-thickness family))
                            (roof-family-coating-thickness family))))
                 vertices)
            (roof-family-thickness family))))
    (shape-layer s (bim-family-layer family))
    (shape-reference s)))

(def-shape/no-provide (wall [p0 : Loc] [p1 : Loc]
                            [bottom-level : Level (current-level)]
                            [top-level : Level (upper-level bottom-level)]
                            [family : Wall-Family (default-wall-family)])
  (let* ((base-height (level-height bottom-level))
         (h (- (level-height top-level) base-height))
         (z (+ base-height (/ h 2)))
         (s (right-cuboid (+z p0 z)
                          (wall-family-thickness family)
                          h
                          (+z p1 z))))
    (shape-layer s (bim-family-layer family))
    (shape-reference s)))
  
(def-shape/no-provide (walls [vertices : Locs]
                             [bottom-level : Level (current-level)]
                             [top-level : Level (upper-level bottom-level)]
                             [family : Wall-Family (default-wall-family)])
  (let ((s 
         (thicken (extrusion (line (map (lambda ([p : Loc])
                                          (+z p (level-height bottom-level)))
                                        vertices))
                             (- (level-height top-level) (level-height bottom-level)))
                  (wall-family-thickness family))))
    (shape-layer s (bim-family-layer family))
    (shape-reference s)))

(def-shape/no-provide (door [wall : Any] [loc : Loc] [family : Any (default-door-family)])
  (let ((wall-e (wall-family-thickness (walls-family wall)))
        (wall-level (walls-bottom-level wall)))
    (shape-reference
     (subtraction
      wall
      (box (+z loc (level-height wall-level))
           (door-family-width family)
           wall-e
           (door-family-height family))))))

(def-shape/no-provide (panel [vertices : Locs] [level : Level (current-level)] [family : Panel-Family (default-panel-family)])
  (let ((p0 (second vertices))
        (p1 (first vertices))
        (p2 (third vertices)))
    (let ((n (vz (/ (panel-family-thickness family) 2)
                 (cs-from-o-vx-vy p0 (p-p p1 p0) (p-p p2 p0)))))
      (let ((s (irregular-prism
                (map (lambda (v) (loc-in-world (p-v v n))) vertices)
                (vec-in-world (v*r n 2)))))
        (shape-layer s (bim-family-layer family))
        (shape-reference s)))))
)

(define-signature bim-extra-ops^
  ([slab-rectangle : (->)]
   [roof-rectangle : (->)]
   [panel-wall : (->)]
   [panel-walls : (->)]))

(define-unit bim-extra-ops@
  (import bim-ops^ bim-levels^)
  (export bim-extra-ops^)
  
  (define (slab-rectangle [p : Loc] [length : Real] [width : Real] [level : Level (current-level)] [family : Slab-Family (default-slab-family)])
    (slab (list p (+x p length) (+xy p length width) (+y p width))
          level
          family))
  
  (define (roof-rectangle [p : Loc] [length : Real] [width : Real] [level : Level (current-level)] [family : Roof-Family (default-roof-family)])
    (roof (list p (+x p length) (+xy p length width) (+y p width))
          level
          family))

  (define (panel-wall [p0 : Loc] [p1 : Loc]
                      [bottom-level : Level (current-level)]
                      [top-level : Level (upper-level bottom-level)]
                      [family : Panel-Family (default-panel-family)])
    (let ((height (- (level-height top-level) (level-height bottom-level))))
      (panel (list p0 p1 (+z p1 height) (+z p0 height))
             bottom-level
             family)))

  (define (panel-walls [vertices : Locs]
                       [bottom-level : Level (current-level)]
                       [top-level : Level (upper-level bottom-level)]
                       [family : Panel-Family (default-panel-family)])
    (for/list ((v0 (in-list vertices))
               (v1 (in-list (cdr vertices))))
      (panel-wall v0 v1 bottom-level top-level family)))
  )