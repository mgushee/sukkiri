;;; sukkiri-data.scm -- Data type converters & validators.
;;;   Copyright © 2014 by Matthew C. Gushee <matt@gushee.net>
;;;   This program is open-source software, released under the GNU General
;;;   Public License v3. See the accompanying LICENSE file for details.

(module sukkiri-data
        *
        (import scheme chicken)
        (import data-structures)
        (use sukkiri-base)
        (use sukkiri-store)
        (use irregex)
        (use srfi-1)
        (use srfi-69)
        (use srfi-19)
        (use srfi-19-period)
 
;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  GENERIC TYPE IDENTIFICATION  -------------------------------------

(define (identify x)
  (cond
    ((boolean? x) `(,boolean . ,x))
    ((integer? x) `(,integer . ,x))
    ((flonum? x) `(,float . ,x))
    ((string? x) `(,string . ,x))
    ((list? x) (map identify x))
    ((vector? x) (list->vector (map identify (vector->list x))))
    (else (eprintf "Can't identify '~A'." x))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  DATE/TIME UTILITIES  ---------------------------------------------

(define (hms->time #!key (h 0) (m 0) (s 0))
  (seconds->time (+ (* 3600 h) (* 60 m) s)))

(define (hms-string->time str #!optional (primary-unit 'min))
  (let* ((hms (map string->number (string-split str ":")))
         (len (length hms)))
    (cond
      ((= len 3) (hms->time h: (car hms) m: (cadr hms) s: (caddr hms)))
      ((and (= len 2) (eqv? primary-unit 'hr)) (hms->time h: (car hms) m: (cadr hms)))
      ((and (= len 2) (eqv? primary-unit 'min)) (hms->time m: (car hms) s: (cadr hms)))
      ((and (= len 1) (eqv? primary-unit 'hr)) (hms->time h: (car hms)))
      ((and (= len 1) (eqv? primary-unit 'min)) (hms->time m: (car hms)))
      ((and (= len 1) (eqv? primary-unit 'sec)) (hms->time s: (car hms)))
      ((= len 0) (hms->time))
      (else (eprintf "Invalid argument for hms-string->time: '~A'\n" str)))))

(define (ymd->date y m d)
  (make-date 0 0 0 0 d m y))

(define (hms->seconds h m s)
  (+ (* 3600 h) (* 60 m) s))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  USER TYPE VALIDATION  --------------------------------------------

(define validators (make-hash-table))

;;; ========================================================================
;;; ------  Set up primitive type validators  ------------------------------

(define (setup-primitive-validators #!optional (custom-validators '()))
  (hash-table-set! validators "integer"
                   (or (alist-ref 'integer custom-validators)
                       integer?))
  (hash-table-set! validators "float"
                   (or (alist-ref 'float custom-validators)
                       flonum?))
  (hash-table-set! validators "boolean"
                   (or (alist-ref 'boolean custom-validators)
                       boolean?))
  (hash-table-set! validators "string"
                   (or (alist-ref 'string custom-validators)
                       string?))
  (hash-table-set! validators "date"
                   (or (alist-ref 'date custom-validators)
                       date?))
  (hash-table-set! validators "time"
                   (or (alist-ref 'time custom-validators)
                       time?))
  (hash-table-set! validators "period"
                   (or (alist-ref 'period custom-validators)
                       number?))
  (hash-table-set! validators "nref"
                   (or (alist-ref 'nref custom-validators)
                       string?))
  (hash-table-set! validators "rref"
                   (or (alist-ref 'rref custom-validators)
                       string?))
  (hash-table-set! validators "sref"
                   (or (alist-ref 'sref custom-validators)
                       string?))
  (hash-table-set! validators "xref"
                   (or (alist-ref 'xref custom-validators)
                       string?)))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  USER TYPE VALIDATORS  --------------------------------------------

;;; ------  String Types  --------------------------------------------------

(define (make-string-type-validator type-name pattern)
  (let ((rx (irregex pattern)))
    (lambda (s)
      (and (irregex-match rx s)
           `(,type-name . ,s)))))

(define (load-string-type-validator db/file type-name)
  (let* ((pattern (get-string-type db/file type-name))
         (val (make-string-type-validator type-name pattern)))
    (hash-table-set! validators type-name val)))

(define (load-string-type-validators db/file)
  (let ((string-types (get-string-types db/file)))
    (for-each
      (lambda (t) (load-string-type-validator db/file t))
      string-types)))

;;; ========================================================================
;;; ------  Number Types  --------------------------------------------------

(define (make-number-type-validator type-name typespec)
  (let* ((minval (alist-ref 'minval typespec))
         (maxval (alist-ref 'maxval typespec))
         (step (alist-ref 'step typespec)))
    (lambda (x)
      (and (or (null? minval)
               (>= x minval))
           (or (null? maxval)
               (<= x maxval))
           (or (null? step)
               (integer?
                  (/ (or (and (null? minval) x)
                         (- x minval)) step)))
           `(,type-name . ,x)))))

(define (load-number-type-validator db/file type-name)
  (let* ((typespec (get-number-type db/file type-name))
         (val (make-number-type-validator type-name typespec)))
    (hash-table-set! validators type-name val)))

(define (load-number-type-validators db/file)
  (let ((number-types (get-number-types db/file)))
    (for-each
      (lambda (t) (load-number-type-validator db/file t))
      number-types)))

;;; ========================================================================
;;; ------  Vocabulary Types  ----------------------------------------------

(define (make-vocab-type-validator type-name terms)
  (lambda (x)
    (let ((mem (member x terms)))
      (and mem 
           `(,type-name . ,x)))))

(define (load-vocab-type-validator db/file type-name)
  (let* ((terms (get-vocab-type db/file type-name))
         (val (make-vocab-type-validator type-name terms)))
    (hash-table-set! validators type-name val)))

(define (load-vocab-type-validators db/file)
  (let ((vocab-types (get-vocab-types db/file)))
    (for-each
      (lambda (t) (load-vocab-type-validator db/file t))
      vocab-types)))

;;; ========================================================================
;;; ------  Struct Types  --------------------------------------------------

(define (validate-struct-member-cardinality card mem)
  (case (string->symbol card)
    ((one) (and (defined? mem)
                (or (not (vector? mem))
                    (= (vector-length mem) 1))))
    ((zoo) (or (undefined? mem)
               (not (vector? mem))
               (<= (vector-length mem) 1)))
    ((ooma) (and (defined? mem)
                 (or (not (vector? mem))
                     (>= (vector-length mem) 1))))
    ((zoma) #t)
    (else (eprintf "Unrecognized value for cardinality: ~A" card))))

(define (zero-allowed? card)
  (or (eqv? card 'zoo) (eqv? card 'zoma)))

(define (validate-member-vector mem-type vec)
  (let loop ((input (vector->list vec))
             (output '()))
    (if (null? input)
      output
      (let ((valid (validate mem-type (car input))))
        (and valid
             (loop (cdr input) (cons valid output)))))))

(define (validate-struct-member memspec value)
  (let* ((rel-name (car memspec))
         (cardinality (cadr memspec))
         (mem-type (caddr memspec))
         (mem (alist-ref rel-name value eqv? #:undefined)))
    (and (validate-struct-member-cardinality cardinality mem)
         (if (vector? mem)
           (validate-member-vector mem-type mem)
           (validate mem-type mem)))))

(define (no-unspecified-members? memspecs value)
  (let ((known-rel-names (append (map car memspecs) '(%TYPE %ID %LABEL))))
    (every (lambda (mem) (member (car mem) known-rel-names)) value)))

(define (validate-struct-members memspecs struct)
  (let loop ((specs memspecs)
             (output '()))
    (if (null? specs)
      output
      (let ((valid (validate-struct-member (car specs) struct)))
        (and valid
             (loop (cdr specs) (cons valid output)))))))

(define (make-struct-type-validator type-name typespec)
  (let ((extensible (car typespec))
        (memspecs (cadr typespec)))
    (lambda (x)
      (let ((members-valid (validate-struct-members memspecs x)))
        (and members-valid
             (or extensible
                 (no-unspecified-members? memspecs x))
             `(,type-name . ,members-valid))))))

(define (load-struct-type-validator db/file type-name)
  (let* ((typespec (get-struct-type db/file type-name))
         (val (make-struct-type-validator type-name typespec)))
    (hash-table-set! validators type-name val)))

(define (load-struct-type-validators db/file)
  (let ((struct-types (get-struct-types db/file)))
    (for-each
      (lambda (t) (load-struct-type-validator db/file t))
      struct-types)))

;;; ========================================================================
;;; ------  Union Types  ---------------------------------------------------

;; N.B.: Returns (SUBTYPE . VALUE), not (UNION-TYPE . VALUE)
(define (make-union-type-validator members)
  (lambda (x)
    (find
      (lambda (memtype) (validate memtype x))
      members)))

(define (load-union-type-validator db/file type-name)
  (let* ((members (get-union-type db/file type-name))
         (val (make-union-type-validator members)))
    (hash-table-set! validators type-name val)))

(define (load-union-type-validators db/file)
  (let ((union-types (get-union-types db/file)))
    (for-each
      (lambda (t) (load-union-type-validator db/file t))
      union-types)))

;;; ========================================================================
;;; ------  Generic Validation  --------------------------------------------

(define (validate type value)
  (or (equal? type "*")
      (and (hash-table-exists? validators type)
           (let* ((validator (hash-table-ref validators type))
                  (validated (validator value)))
             (and validated
                  `(,validated . ,value))))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  HIGH-LEVEL INTERFACE  --------------------------------------------

(define (store-struct db/file str)
  (if (validate type members)
    (add-struct db/file str)
    (eprintf "Invalid struct: failed type validation.")))

(define (retrieve-struct db/file id)
  (get-struct db/file id))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

) ; END MODULE

;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ------------------------------------------------------------------------

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

;;; ========================================================================
;;; ------------------------------------------------------------------------

