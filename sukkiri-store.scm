;;; sukkiri-store.scm -- SQLite3 interface for Sukkiri.
;;;   Copyright © 2014 by Matthew C. Gushee <matt@gushee.net>
;;;   This program is open-source software, released under the GNU General
;;;   Public License v3. See the accompanying LICENSE file for details.

(module sukkiri-store
        *
        (import scheme chicken)
        (import extras)
        (import files)
        (import data-structures)
        (import ports)
        (import irregex)
        (import srfi-1)
        (use sql-de-lite)
        (use srfi-19)
        (use srfi-19-period)
        (use sukkiri-base)

;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  CURRENT DATABASE  ------------------------------------------------

(define %db-file% (make-parameter #f))

(define %current-db% (make-parameter #f))

(define (connect #!optional (filespec (%db-file%)))
  (if filespec
    (let ((db (open-database filespec)))
      (%current-db% db)
      db)
    (error "No database specified.")))

(define (disconnect)
  (let ((db (%current-db%)))
    (and db
         (close-database db)
         (%current-db% #f))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  UTILITY FUNCTIONS  -----------------------------------------------

(define iso-format "~Y-~m-~dT~H:~M:~S")

(define << values)

(define db->integer string->number)

(define db->float string->number)

(define db->string identity)

(define (db->boolean dbval)
  (cond
    ((string=? dbval "0") #f)
    ((string=? dbval "1") #t)
    (else (eprintf "'~A' is not a boolean value" dbval))))

(define (db->date dbval)
  (string->date dbval iso-format))

(define (db->time dbval)
  (date->time (string->date dbval iso-format)))

(define db->period string->number)

(define integer->db number->string)

(define float->db number->string)

(define string->db identity)

(define (boolean->db b)
  (if b 1 0))

(define (date->db d)
  (date->string d iso-format))

(define (time->db t)
  (date->string (time->date t) iso-format))

;; Currently a period is just a seconds value
(define period->db identity)

(define validate-integer integer?)

(define validate-float flonum?)

(define validate-boolean boolean?)

(define validate-string string?)

(define validate-date date?)

(define validate-time time?)

(define validate-period number?)

(define (primitive? typespec)
  (memv
    (string->symbol typespec)
    '(integer float boolean string date time period nref rref xref sref)))

(define (not-implemented . args)
  (error "Not implemented."))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  DATABASE SETUP  --------------------------------------------------

;; FILENAME -> ()
(define create-db (make-parameter not-implemented))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  USER-DEFINED TYPE MANAGEMENT  ------------------------------------

;; DATABASE -> ()
(define begin-transaction (make-parameter not-implemented))

;; DATABASE/FILE -> PROC -> ()
(define do-query (make-parameter not-implemented))

;; DATABASE -> TYPENAME -> TYPECLASS -> ()
(define add-general-type (make-parameter not-implemented))

;; DATABASE -> TYPENAME -> [UNION?] -> ()
(define delete-general-type (make-parameter not-implemented))

;; DATABASE/FILE -> TYPENAME -> PATTERN -> [DESCRIPTION] -> ()
(define add-string-type (make-parameter not-implemented))

;; DATABASE/FILE -> TYPENAME -> {MINVAL} -> {MAXVAL} -> {STEP} -> {DIGITS} -> {DESCRIPTION} -> ()
(define add-number-type (make-parameter not-implemented))

;; DATABASE/FILE -> TYPENAME -> TERMS -> ()
(define add-vocab-type (make-parameter not-implemented))

(define (add-struct-type db/file name #!key (extensible #t) (members '())
                                            (description '()))
  (do-query
    db/file
    (lambda (db)
      (let ((st-main (sql/transient db add-struct-type-query))
            (st-mem (sql db add-struct-member-query)))
        (exec st-main name (if extensible 1 0) description)
        (for-each
          (lambda (mem)
            (exec st-mem (symbol->string (car mem)) name (cadr mem) (caddr mem)))
          members))
        (add-general-type db name "struct"))))

(define (add-union-type db/file name members)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql db add-union-type-member-query)))
        (for-each
          (lambda (mem) (exec st name mem))
          members))
      (add-general-type db name "union"))))

(define (update-string-type db/file name pattern)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db update-string-type-query)))
        (exec st pattern name)))))

(define (update-number-type db/file name #!key (minval #f) (maxval #f)
                                               (step #f) (digits #f))
  (do-query
    db/file
    (lambda (db)
      (let* ((st-current (sql/transient db get-number-type-query))
             (st-update (sql/transient db update-number-type-query))
             (current-vals (query fetch-alist st-current name))
             (minval* (or minval (alist-ref 'minval current-vals)))
             (maxval* (or maxval (alist-ref 'maxval current-vals)))
             (step* (or step (alist-ref 'step current-vals)))
             (digits* (or digits (alist-ref 'digits current-vals))))
        (exec st-update minval* maxval* step* digits* name)))))

(define (update-vocab-type db/file name #!key (terms+ '()) (terms- '()))
  (do-query
    db/file
    (lambda (db)
      (let ((st-add (sql db add-vocab-type-term-query))
            (st-del (sql db update-vocab-type-delete-term-query)))
        (for-each
          (lambda (term) (exec st-add name term))
          terms+)
        (for-each
          (lambda (term) (exec st-del name term))
          terms-)))))

(define (update-struct-type db/file name #!key (extensible #t) (members+ '())
                                               (members- '()) (members* '()))
  (do-query
    db/file
    (lambda (db)
      (let ((st-ext (sql/transient db update-struct-type-extensible-query))
            (st-add (sql db add-struct-member-query))
            (st-del (sql db delete-struct-member-query))
            (st-current (sql db get-struct-member-query))
            (st-upd (sql db update-struct-member-query)))
        (exec st-ext extensible name)
        (for-each
          (lambda (mem)
            (exec st-add
                  (alist-ref 'rel-name mem)
                  name
                  (alist-ref 'cardinality mem)
                  (alist-ref 'type mem)))
          members+)
        (for-each
          (lambda (mem) (exec st-del name mem))
          members-)
        (for-each
          (lambda (mem)
            (let* ((rel-name (alist-ref 'rel-name mem))
                   (current-values
                     (query fetch-alist st-current name rel-name))
                   (rel-name* (or (alist-ref 'new-rel-name mem) rel-name))
                   (cardinality* (or (alist-ref 'cardinality mem)
                                     (alist-ref 'cardinality current-values)))
                   (mem-type* (or (alist-ref 'mem-type mem)
                                  (alist-ref 'mem-type current-values))))
              (exec st-upd rel-name* cardinality* mem-type* name rel-name)))
          members*)))))

(define (update-union-type db/file name #!key (members+ '()) (members- '()))
  (do-query
    db/file
    (lambda (db)
      (let ((st-add (sql db add-union-type-member-query))
            (st-del (sql db update-union-type-delete-member-query)))
        (for-each
          (lambda (mem) (exec st-add name mem))
          members+)
        (for-each
          (lambda (mem) (exec st-del name mem))
          members-)))))

(define (delete-string-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db delete-string-type-query)))
        (exec st name))
      (delete-general-type db name))))

(define (delete-number-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db delete-number-type-query)))
        (exec st name))
      (delete-general-type db name))))

(define (delete-vocab-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db delete-vocab-type-query)))
        (exec st name))
      (delete-general-type db name)))) 

(define (delete-struct-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st-main (sql/transient db delete-struct-type-query))
            (st-mem (sql/transient db delete-struct-members-query)))
        (exec st-mem name)
        (exec st-main name))
      (delete-general-type db name))))

(define (delete-union-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db delete-union-type-query)))
        (exec st name))
      (delete-general-type db name #t))))

(define (get-string-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-string-type-query)))
        (query fetch-value st name)))))

(define (get-number-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-number-type-query)))
        (query fetch-alist st name)))))

(define (get-vocab-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-vocab-terms-query)))
        (query fetch-column st name)))))

(define (get-struct-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let* ((st (sql/transient db get-struct-type-query))
             (memspecs*
               (query fetch-alists st name))
             (extensible
               (= (alist-ref 'extensible (car memspecs*)) 1))
             (memspecs
               (map
                 (lambda (ms)
                   `(,(string->symbol (alist-ref 'rel_name ms))
                     ,(alist-ref 'cardinality ms) ,(alist-ref 'mem_type ms)))
                 memspecs*)))
        `(,extensible ,memspecs)))))

(define (get-union-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-union-type-members-query)))
        (query fetch-column st name)))))

(define (get-string-types db/file)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-string-types-query)))
        (query fetch-column st)))))

(define (get-number-types db/file)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-number-types-query)))
        (query fetch-column st)))))

(define (get-vocab-types db/file)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-vocab-types-query)))
        (query fetch-column st)))))

(define (get-struct-types db/file)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-struct-types-query)))
        (query fetch-column st)))))

(define (get-union-types db/file)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-union-types-query)))
        (query fetch-column st)))))

(define (get-type-class db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db get-type-class-query)))
        (fetch-value st name)))))

(define (get-type db/file name)
  (do-query
    db/file
    (lambda (db)
      (let ((cls (get-type-class db name)))
        (case (string->symbol cls)
          ((primitive) (string->symbol name))
          ((string) (get-string-type db name))
          ((number) (get-number-type db name))
          ((vocab) (get-vocab-type db name))
          ((struct) (get-struct-type db name))
          ((union) (get-union-type db name))
          (else (eprintf "Invalid type class")))))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  STATEMENT MANIPULATION  ------------------------------------------

;;; ------  Queries  -------------------------------------------------------

(define add-statement-query
  "INSERT INTO statements (s, p, o, t) VALUES (?, ?, ?, ?);")

(define delete-statements-s-query
  "DELETE FROM statements WHERE s = ?;")

(define delete-statements-p-query
  "DELETE FROM statements WHERE p = ?;")

(define delete-statements-o-query
  "DELETE FROM statements WHERE o = ?;")

(define delete-statements-t-query
  "DELETE FROM statements WHERE t = ?;")

(define delete-statements-sp-query
  "DELETE FROM statements WHERE s = ? AND p = ?;")

(define delete-statements-so-query
  "DELETE FROM statements WHERE s = ? AND o = ?;")

(define delete-statements-st-query
  "DELETE FROM statements WHERE s = ? AND t = ?;")

(define delete-statements-po-query
  "DELETE FROM statements WHERE p = ? AND o = ?;")

(define delete-statements-pt-query
  "DELETE FROM statements WHERE p = ? AND t = ?;")

(define delete-statements-spo-query
  "DELETE FROM statements WHERE s = ? AND p = ? AND o = ?;")

(define delete-statements-spt-query
  "DELETE FROM statements WHERE s = ? AND p = ? AND t = ?;")

(define update-statement-object-query
  "UPDATE statements SET o = ?, t = ?, dt = datetime('now')  WHERE s = ? AND p = ? AND o = ?;")

(define exists-s-query
  "EXISTS (SELECT id FROM statements WHERE s = ?);") 

(define exists-p-query
  "EXISTS (SELECT id FROM statements WHERE p = ?);") 

(define exists-o-query
  "EXISTS (SELECT id FROM statements WHERE o = ?);") 

(define exists-t-query
  "EXISTS (SELECT id FROM statements WHERE t = ?);") 

(define exists-sp-query
  "EXISTS (SELECT id FROM statements WHERE s = ? AND p = ?);") 

(define exists-so-query
  "EXISTS (SELECT id FROM statements WHERE s = ? AND o = ?);") 

(define exists-st-query
  "EXISTS (SELECT id FROM statements WHERE s = ? AND t = ?);") 

(define exists-po-query
  "EXISTS (SELECT id FROM statements WHERE p = ? AND o = ?);") 

(define exists-pt-query
  "EXISTS (SELECT id FROM statements WHERE p = ? AND t = ?);") 

(define exists-spo-query
  "EXISTS (SELECT id FROM statements WHERE s = ? AND p = ? AND o = ?);") 

(define exists-spt-query
  "EXISTS (SELECT id FROM statements WHERE s = ? AND p = ? AND t = ?);") 

(define get-statements-s-query
  "SELECT s, p, o, t FROM statements WHERE s = ?;")

(define get-statements-p-query
  "SELECT s, p, o, t FROM statements WHERE p = ?;")

(define get-statements-o-query
  "SELECT s, p, o, t FROM statements WHERE o = ?;")

(define get-statements-t-query
  "SELECT s, p, o, t FROM statements WHERE t = ?;")

(define get-statements-sp-query
  "SELECT s, p, o, t FROM statements WHERE s = ? AND p = ?;")

(define get-statements-so-query
  "SELECT s, p, o, t FROM statements WHERE s = ? AND o = ?;")

(define get-statements-st-query
  "SELECT s, p, o, t FROM statements WHERE s = ? AND t = ?;")

(define get-statements-po-query
  "SELECT s, p, o, t FROM statements WHERE p = ? AND o = ?;")

(define get-statements-pt-query
  "SELECT s, p, o, t FROM statements WHERE p = ? AND t = ?;")

(define get-statements-spt-query
  "SELECT s, p, o, t FROM statements WHERE s = ? AND p = ? AND t = ?;")

;;; ========================================================================
;;; ------  Functions  -----------------------------------------------------

(define (add-statement db/file s p o t)
  (do-query
    db/file
    (lambda (db)
      (let ((st-add (sql/transient db add-statement-query)))
        (exec st-add s p o t)))))

(define (add-statements db/file sts)
  (do-query
    db/file
    (lambda (db)
      (let ((st-add (sql db add-statement-query)))
        (for-each
          (lambda (stmt)
            (let ((s (car stmt))
                  (p (cadr stmt))
                  (t* (caddr stmt))
                  (o* (cdddr stmt)))
              (let-values (((t o) (prepare-object db t* o*)))
                (exec st-add s p o t))))
          sts)))))

(define (delete-statements db/file #!key (s #f) (st #f) (p #f) (o #f) (t #f))
  (let-values (((q-del params)
                  (cond
                    ((and s p o) (<< delete-statements-spo-query `(,s ,p ,o)))
                    ((and s p t) (<< delete-statements-spt-query `(,s ,p ,t)))
                    ((and s p) (<< delete-statements-sp-query `(,s ,p)))
                    ((and s o) (<< delete-statements-so-query `(,s ,o)))
                    ((and s t) (<< delete-statements-st-query `(,s ,t)))
                    ((and p o) (<< delete-statements-po-query `(,p ,o)))
                    ((and p t) (<< delete-statements-pt-query `(,p ,t)))
                    (s (<< delete-statements-s-query `(,s)))
                    (p (<< delete-statements-p-query `(,p)))
                    (o (<< delete-statements-o-query `(,o)))
                    (t (<< delete-statements-t-query `(,t)))
                    (else (error "Invalid arguments for delete-statements.")))))
    (do-query
      db/file
      (lambda (db)
        (let ((st-del (sql/transient db q-del)))
          (apply exec `(,st-del ,@params)))))))

(define (update-statement-object db/file s p o)
  (do-query
    db/file
    (lambda (db)
      (let ((st (sql/transient db update-statement-object-query)))
        (exec st s p o)))))

(define (statement-exists? db/file #!key (s #f) (p #f) (o #f) (t #f))
  (let-values (((q-ex params)
                  (cond
                    ((and s p o) (<< exists-spo-query `(,s ,p ,o)))
                    ((and s p t) (<< exists-spt-query `(,s ,p ,t)))
                    ((and s p) (<< exists-sp-query `(,s ,p)))
                    ((and s o) (<< exists-so-query `(,s ,o)))
                    ((and s t) (<< exists-st-query `(,s ,t)))
                    ((and p o) (<< exists-po-query `(,p ,o)))
                    ((and p t) (<< exists-pt-query `(,p ,t)))
                    (s (<< exists-s-query `(,s)))
                    (p (<< exists-p-query `(,p)))
                    (o (<< exists-o-query `(,o)))
                    (t (<< exists-t-query `(,t)))
                    (else (error "Invalid arguments for statement-exists?.")))))
    (do-query
      db/file
      (lambda (db)
        (let ((st-ex (sql/transient db q-ex)))
          (apply exec `(,st-ex ,@params)))))))

(define (object->ext-type statement)
  (let* ((subject (alist-ref 's statement))
         (prop (alist-ref 'p statement))
         (type (alist-ref 't statement))
         (raw-object (alist-ref 'o statement))
         (object
           (case (string->symbol type)
             ((integer) (db->integer raw-object))
             ((float) (db->float raw-object))
             ((boolean) (db->boolean raw-object))
             ((date) (db->date raw-object))
             ((time) (db->time raw-object))
             ((period) (db->period raw-object))
             (else raw-object))))
    `((s . ,subject) (p . ,prop) (o . ,object))))

(define (get-statements db/file #!key (s #f) (p #f) (o #f) (t #f))
  (let-values (((q-get params)
                (cond
                  ((and s p t) (<< get-statements-spt-query `(,s ,p ,t)))
                  ((and s p) (<< get-statements-sp-query `(,s ,p)))
                  ((and s o) (<< get-statements-so-query `(,s ,o)))
                  ((and s t) (<< get-statements-st-query `(,s ,t)))
                  ((and p o) (<< get-statements-po-query `(,p ,o)))
                  ((and p t) (<< get-statements-pt-query `(,p ,t)))
                  (s (<< get-statements-s-query `(,s)))
                  (p (<< get-statements-p-query `(,p)))
                  (o (<< get-statements-o-query `(,o)))
                  (t (<< get-statements-t-query `(,t)))
                  (else (error "Invalid arguments for get-statements")))))
    (do-query
      db/file
      (lambda (db)
        (let* ((st-get (sql/transient db q-get))
               (raw-results (apply query `(,fetch-alists ,st-get ,@params))))
          (map object->ext-type raw-results))))))
      
;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  HIGH-LEVEL INTERFACE  --------------------------------------------

(define (prepare-object db/file type obj)
  (let ((class (get-type-class db/file type)))
    (cond
      ((equal? type "boolean") (values type (boolean->db obj)))
      ((equal? type "date") (values type (date->db obj)))
      ((equal? type "time") (values type (time->db obj)))
      ((equal? type "period") (values type (period->db obj)))
      ((equal? class "struct") (values "nref" (add-struct db/file obj)))
      (else (values type obj)))))
 
(define (flatten-list-objects db/file str)
  (let loop ((stmts-in str) (stmts-out '()))
    (if (null? stmts-in)
      stmts-out
      (let ((p (caar stmts-in))
            (o (cdar stmts-in)))
        (if (list? o)
          (loop
            (cdr stmts-in)
            (append stmts-out
              (map (lambda (o*) `(,p . ,o*)) o)))
          (loop
            (cdr stmts-in)
            (cons `(,p . ,o) stmts-out)))))))

(define (add-struct db/file str)
  (let ((id (alist-ref '%ID str))
        (type (alist-ref '%TYPE str))
        (members
          (remove
            (lambda (elt) (eqv? (car elt) '%ID))
            str)))
    (add-statements db/file (map (lambda (m) (cons id m)) members))))

(define (get-struct db/file id)
  (let ((statements (get-statements db/file s: id)))
    (cons
      `(%ID . ,id) 
      (map
        (lambda (elt)
          `(,(alist-ref 'p elt) . ,(alist-ref 'o elt)))
        statements))))

(define (init-store filespec #!optional (replace #f))
  (%db-file% filespec)
  (when replace
    (delete-file* filespec))
  (unless (file-exists? filespec)
    (create-db filespec)))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

) ; END MODULE

;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ------------------------------------------------------------------------

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

;;; ========================================================================
;;; ------------------------------------------------------------------------

