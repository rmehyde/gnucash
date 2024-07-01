;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; budget.scm: budget report
;;
;; (C) 2005 by Chris Shoemaker <c.shoemaker@cox.net>
;;
;; based on cash-flow.scm by:
;; Herbert Thoma <herbie@hthoma.de>
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, contact:
;;
;; Free Software Foundation           Voice:  +1-617-542-5942
;; 51 Franklin Street, Fifth Floor    Fax:    +1-617-542-2652
;; Boston, MA  02110-1301,  USA       gnu@gnu.org
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-module (gnucash reports standard budget))

(use-modules (gnucash engine))
(use-modules (gnucash utilities))
(use-modules (gnucash core-utils))
(use-modules (gnucash app-utils))
(use-modules (gnucash report))

(use-modules (srfi srfi-1))
(use-modules (ice-9 match))
(use-modules (ice-9 receive))

(define reportname (N_ "Custom Budget Report"))

;; define all option's names so that they are properly defined
;; in *one* place.

(define optname-display-depth
  (N_ "Account Display Depth"))
(define optname-show-subaccounts (N_ "Always show sub-accounts"))
(define optname-accounts (N_ "Account"))

(define optname-show-budget (N_ "Show Budget"))
(define opthelp-show-budget (N_ "Display a column for the budget values."))
(define optname-show-notes (N_ "Show Budget Notes"))
(define opthelp-show-notes (N_ "Display a column for the budget notes."))
(define optname-show-actual (N_ "Show Actual"))
(define opthelp-show-actual (N_ "Display a column for the actual values."))
(define optname-show-difference (N_ "Show Difference"))
(define opthelp-show-difference (N_ "Display the difference as budget - actual."))
(define optname-accumulate (N_ "Rollover budget difference"))
(define opthelp-accumulate (N_ "Values are accumulated across periods."))
(define optname-selected-only (N_ "Exclude unselected amounts"))
(define opthelp-selected-only (N_ "Accounts not displayed will not be counted in their parent account values."))
(define optname-show-totalcol (N_ "Show Column with Totals"))
(define opthelp-show-totalcol (N_ "Display a column with the row totals."))
(define optname-show-zb-accounts (N_ "Include accounts with zero total balances and budget values"))
(define opthelp-show-zb-accounts (N_ "Include accounts with zero total (recursive) balances and budget values in this report."))


(define optname-use-budget-period-range
  (N_ "Report for range of budget periods"))
(define opthelp-use-budget-period-range
  (N_ "Create report for a budget period range instead of the entire budget."))

(define optname-budget-period-start (N_ "Range start"))
(define opthelp-budget-period-start
  (N_ "Select a budget period type that starts the reporting range."))
(define optname-budget-period-start-exact (N_ "Exact start period"))
(define opthelp-budget-period-start-exact
  (N_ "Select exact period that starts the reporting range."))

(define optname-budget-period-end (N_ "Range end"))
(define opthelp-budget-period-end
  (N_ "Select a budget period type that ends the reporting range."))
(define optname-budget-period-end-exact (N_ "Exact end period"))
(define opthelp-budget-period-end-exact
  (N_ "Select exact period that ends the reporting range."))

(define optname-period-collapse-before (N_ "Include collapsed periods before selected."))
(define opthelp-period-collapse-before (N_ "Include in report previous periods as single collapsed column (one for all periods before starting)"))
(define optname-period-collapse-after (N_ "Include collapsed periods after selected."))
(define opthelp-period-collapse-after (N_ "Include in report further periods as single collapsed column (one for all periods after ending and to the end of budget range)"))

(define optname-bottom-behavior (N_ "Flatten list to depth limit"))
(define opthelp-bottom-behavior
  (N_ "Displays accounts which exceed the depth limit at the depth limit."))

(define optname-budget (N_ "Budget"))

;;List of common helper functions, that is not bound only to options generation or report evaluation
(define (get-option-val options pagename optname)
  (gnc:option-value
   (gnc:lookup-option options pagename optname)))

(define (set-option-enabled options page opt-name enabled)
  (gnc-option-db-set-option-selectable-by-name
   options page opt-name enabled))

;; Debug logging
(define current-time-string (number->string (current-time)))
(define (debug-log message)
  (let* ((out (open-file
                 (string-append "/home/reese/.local/share/gnucash/report-logs/custom-budget-report-" current-time-string ".log")
                 "a")))
    (display message out)
    (newline out)
    (close-output-port out)))

;; WIP Get Unselected Child Accounts
;; TODO: move
;; TODO: update comment below to reflect that this case is fixed
  ;; [x] top
  ;;   [ ] parent
  ;;     [ ] sibling accounts
  ;;     [ ] sub accounts
  ;;       [x] child account
  ;; We can't simply subtract 'parent' from 'top' because the inner child still needs to be included :(
  ;; Maybe a solution is to toss this approach and just make a flat list of all unselected accounts, then fetch their
  ;;   balances _without their children_. How hard/easy is that to do?
  ;; Probably we want to recurse from the top down, deciding what to do with each account. If it's not selected, remove
  ;; it. Then recurse down into its children, and add any that _are_ selected. Similarly, if it's not selected, add it
  ;; to the subtraction list and keep recursing
(define (descendant-additions-subtractions parent-acct selected-accts)
  ;; map-accts-by-guid takes a list of accounts and returns a hash table keyed by account GUID
  (define (map-accts-by-guid acct-list)
    (define accts-map (make-hash-table (length acct-list)))
    (for-each
      (lambda (acct)
        (hash-set! accts-map (gncAccountGetGUID acct) acct))
      acct-list)
    accts-map)

  (define (get-add-subtract-descendants acct selected-accts-map)
    (define (is-selected acct) (not (eq? (hash-ref selected-accts-map (gncAccountGetGUID acct) 'not-found) 'not-found)))
    (define (get-add-subtract-descendants-helper cur-acct is-root)
;      (debug-log (string-append "at top of helper\n  subtract accounts is: " (object->string subtract-accts)
;                   "\n  add accounts is: " (object->string add-accts)))
      ;; setup list of results
      (define result '())
      (let ((parent-acct (gnc-account-get-parent cur-acct))
             (children-accts (gnc-account-get-children-sorted cur-acct)))
        (cond
          ;; if this account is selected and its parent is (or we're on the root account, ignoring parent) no need to do
          ;;   anything, this account is already included in its parent total
          ((and (is-selected cur-acct) (or (is-selected parent-acct) is-root)) #f)
          ;; same deal if neither this one or its parent are selected: we've already subtracted the total of the parent
          ;;   account including this one so no need to do anything
          ((and (not (is-selected cur-acct)) (not (is-selected parent-acct))) #f)
          ;; if this account is selected but its parent is not we need to add this account to the 'add-accts' list since
          ;;   its value is not included in its parent
          ((and (is-selected cur-acct) (not (is-selected parent-acct)))
            (set! result (cons (list 'add-acct cur-acct) result)))
          ;; if this account is not selected but its parent is, we need to add it to the 'subtract-accts' list since its
          ;;   value needs to be subtracted from the parent total
          ((and (not (is-selected cur-acct)) (is-selected parent-acct))
            (set! result (cons (list 'subtract-acct cur-acct) result)))
        (else
          (debug-log "ERROR should not hit this case")
          result))
        ;; recurse into children
        (for-each
          (lambda (child)
            (set! result (append result (get-add-subtract-descendants-helper child #f))))
          children-accts))
        result)

    (define acct-actions (get-add-subtract-descendants-helper parent-acct #t ))
    (define subtract-accts '())
    (define add-accts '())
    (for-each
      (lambda (item)
        (cond
          ((eq? (car item) 'add-acct)
            (set! add-accts (cons (second item) add-accts)))
          ((eq? (car item) 'subtract-acct)
            (set! subtract-accts (cons (second item) subtract-accts)))))
      acct-actions)

    (if (or (> (length add-accts) 0) (> (length subtract-accts) 0))
      (debug-log
        (string-append "Account " (xaccAccountGetName parent-acct) " would subtract the following accounts:\n    "
          (object->string (map (lambda (acct) (xaccAccountGetName acct)) subtract-accts))
          "\nand add the following accounts:\n    "
          (object->string (map (lambda (acct) (xaccAccountGetName acct)) add-accts)) "\n"))
      )
    (values subtract-accts add-accts))

  (get-add-subtract-descendants parent-acct (map-accts-by-guid selected-accts)))


;; options generator
(define (budget-report-options-generator)
  (let* ((options (gnc:new-options))
         (add-option
          (lambda (new-option)
            (gnc:register-option options new-option)))
         (period-options
          (list (vector 'first (N_ "First budget period"))
                (vector 'previous (N_ "Previous budget period"))
                (vector 'current (N_ "Current budget period"))
                (vector 'next (N_ "Next budget period"))
                (vector 'last (N_ "Last budget period"))
                (vector 'manual (N_ "Manual period selection"))))
         (ui-use-periods #f)
         (ui-start-period-type 'current)
         (ui-end-period-type 'next))

    (gnc:register-option
     options
     (gnc:make-budget-option
      gnc:pagename-general optname-budget
      "a" (N_ "Budget to use.")))

    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-general optname-accumulate
      "b" opthelp-accumulate #f))

    (add-option
      (gnc:make-simple-boolean-option
        gnc:pagename-general optname-selected-only
        "b" opthelp-selected-only #f))

    (add-option
     (gnc:make-complex-boolean-option
      gnc:pagename-general optname-use-budget-period-range
      "f" opthelp-use-budget-period-range #f #f
      (lambda (value)
        (for-each
         (lambda (opt)
           (set-option-enabled options gnc:pagename-general opt value))
         (list optname-budget-period-start optname-budget-period-end
               optname-period-collapse-before optname-period-collapse-after))

        (set-option-enabled options gnc:pagename-general
                            optname-budget-period-start-exact
                            (and value (eq? 'manual ui-start-period-type)))

        (set-option-enabled options gnc:pagename-general
                            optname-budget-period-end-exact
                            (and value (eq? 'manual ui-end-period-type)))

        (set! ui-use-periods value))))

    (add-option
     (gnc:make-multichoice-callback-option
      gnc:pagename-general optname-budget-period-start
      "g1.1" opthelp-budget-period-start 'current period-options #f
      (lambda (new-val)
        (set-option-enabled options gnc:pagename-general
                            optname-budget-period-start-exact
                            (and ui-use-periods (eq? 'manual new-val)))
        (set! ui-start-period-type new-val))))

    (add-option
     (gnc:make-number-range-option
      gnc:pagename-general optname-budget-period-start-exact
      "g1.2" opthelp-budget-period-start-exact
      ;; FIXME: It would be nice if the max number of budget periods (60) was
      ;; defined globally somewhere so we could reference it here.  However, it
      ;; only appears to be defined currently in src/gnome/glade/budget.glade.
      1 1 60 0 1))

    (add-option
     (gnc:make-multichoice-callback-option
      gnc:pagename-general optname-budget-period-end
      "g2.1" opthelp-budget-period-end 'next period-options #f
      (lambda (new-val)
        (set-option-enabled options gnc:pagename-general
                            optname-budget-period-end-exact
                            (and ui-use-periods (eq? 'manual new-val)))
        (set! ui-end-period-type new-val))))

    (add-option
     (gnc:make-number-range-option
      gnc:pagename-general optname-budget-period-end-exact
      "g2.2" opthelp-budget-period-end-exact
      ;; FIXME: It would be nice if the max number of budget periods (60) was
      ;; defined globally somewhere so we could reference it here.  However, it
      ;; only appears to be defined currently in src/gnome/glade/budget.glade.
      1 1 60 0 1))
    ;; accounts to work on

    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-general optname-period-collapse-before
      "g3" opthelp-period-collapse-before #t))

    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-general optname-period-collapse-after
      "g4" opthelp-period-collapse-after #t))

    (gnc:options-add-account-selection!
     options gnc:pagename-accounts optname-display-depth
     optname-show-subaccounts optname-accounts "a" 2
     (lambda ()
       (gnc:filter-accountlist-type
        (list ACCT-TYPE-ASSET ACCT-TYPE-LIABILITY ACCT-TYPE-INCOME
              ACCT-TYPE-EXPENSE)
        (gnc-account-get-descendants-sorted (gnc-get-current-root-account))))
     #f)

    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-accounts optname-bottom-behavior
      "c" opthelp-bottom-behavior #f))

    ;; columns to display
    (add-option
     (gnc:make-complex-boolean-option
      gnc:pagename-display optname-show-budget
      "s1" opthelp-show-budget #t #f
      (lambda (x)
        (set-option-enabled options gnc:pagename-display optname-show-notes x))))
    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-display optname-show-notes
      "s15" opthelp-show-notes #t))
    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-display optname-show-actual
      "s2" opthelp-show-actual #t))
    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-display optname-show-difference
      "s3" opthelp-show-difference #f))
    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-display optname-show-totalcol
      "s4" opthelp-show-totalcol #f))
    (add-option
     (gnc:make-simple-boolean-option
      gnc:pagename-display optname-show-zb-accounts
      "s5" opthelp-show-zb-accounts #t))

    ;; Set the general page as default option tab
    (gnc:options-set-default-section options gnc:pagename-general)

    options))

;; creates a footnotes collector. (make-footnote-collector) => coll
;; (coll elt) if elt is not null or "", adds elt to store, returns
;; html-text containing ref eg. <sup title='note'>1</sup>. calling
;; (coll 'list) returns html-text containing <ol> of all stored elts
(define (make-footnote-collector)
  (let ((notes '()) (num 0))
    (match-lambda
      ('list
       (let lp ((notes notes) (res '()))
         (match notes
           (() (gnc:make-html-text (gnc:html-markup-ol res)))
           ((note . rest) (lp rest (cons note res))))))
      ((or #f "") "")
      (note
       (set! notes (cons (gnc:html-string-sanitize note) notes))
       (set! num (1+ num))
       (let ((text (gnc:make-html-text
                    " " (gnc:html-markup "sup" (number->string num)))))
         (gnc:html-text-set-style! text "sup" 'attribute `("title" ,note))
         text)))))

;; Create the html table for the budget report
;;
;; Parameters
;;   html-table - HTML table to fill in
;;   acct-table - Table of accounts to use
;;   budget - budget to use
;;   params - report parameters
(define (gnc:html-table-add-budget-values!
         html-table acct-table budget params)

  ; log the html-acct-table utility object
  (debug-log (object->string acct-table))
  ; create list of accounts from account table


  (let* ((get-val (lambda (alist key)
                    (let ((lst (assoc-ref alist key)))
                      (and lst (car lst)))))
         (show-actual? (get-val params 'show-actual))
         (show-budget? (get-val params 'show-budget))
         (show-diff? (get-val params 'show-difference))
         (show-note? (get-val params 'show-note))
         (footnotes (get-val params 'footnotes))
         (accumulate? (get-val params 'use-envelope))
         (show-totalcol? (get-val params 'show-totalcol))
         (use-ranges? (get-val params 'use-ranges))
         (accounts (get-val params 'accounts))
         (selected-only? (get-val params 'selected-only))
         (num-rows (gnc:html-acct-table-num-rows acct-table))
         (numcolumns (gnc:html-table-num-columns html-table))
         ;; WARNING: we implicitly depend here on the details of
         ;; gnc:html-table-add-account-balances.  Specifically, we
         ;; assume that it makes twice as many columns as it uses for
         ;; account labels.  For now, that seems to be a valid
         ;; assumption.
         (colnum (quotient numcolumns 2)))

    ;; Calculate the value to use for the budget of an account for a
    ;; specific set of periods.  If there is 1 period, use that
    ;; period's budget value.  Otherwise, sum the budgets for all of
    ;; the periods.
    ;;
    ;; Parameters:
    ;;   budget - budget to use
    ;;   acct - account
    ;;   periodlist - list of budget periods to use
    ;;
    ;; Return value:
    ;;   Budget sum
    (define (gnc:get-single-account-periodlist-budget-value budget acct periodlist)
      (apply +
             (map
              (lambda (period)
                (gnc:get-account-period-rolledup-budget-value budget acct period))
              periodlist)))

    (define (gnc:get-account-periodlist-budget-value budget acct periodlist)
      (receive (subtract-accts add-accts) (descendant-additions-subtractions acct accounts)
;                (debug-log (string-append "subtract accounts:\n  " (object->string subtract-accts)
;                               "\nadd accounts:\n  " (object->string add-accts) "\n  selected-only? " (object->string selected-only?)))
        (let
          ((acct-budget-val (gnc:get-single-account-periodlist-budget-value budget acct periodlist))
           (subtract-budget-offset-val
             (if selected-only?
               (apply +
                 (map
                   (lambda (sub-acct)
                     (gnc:get-single-account-periodlist-budget-value budget sub-acct periodlist))
                   subtract-accts))
               0))
           (add-budget-offset-val
             (if selected-only?
               (apply +
                 (map
                   (lambda (add-acct)
                     (gnc:get-single-account-periodlist-budget-value budget add-acct periodlist))
                   add-accts))
               0)))
          (debug-log (string-append "subtract offset val: " (object->string subtract-budget-offset-val)
                       " , add offset val: " (object->string add-budget-offset-val)))
          (+ (- acct-budget-val subtract-budget-offset-val) add-budget-offset-val))))
    
    ;; Calculate the value to use for the actual of an account for a
    ;; specific set of periods.  This is the sum of the actuals for
    ;; each of the periods.
    ;;
    ;; Parameters:
    ;;   budget - budget to use
    ;;   acct - account
    ;;   periodlist - list of budget periods to use
    ;;
    ;; Return value:
    ;;   Budget sum
    (define (gnc:get-single-account-periodlist-actual-value budget acct periodlist)
      (apply + (map
                (lambda (period)
                  (gnc-budget-get-account-period-actual-value budget acct period))
                periodlist)))

    (define (gnc:get-account-periodlist-actual-value budget acct periodlist)
      (receive (subtract-accts add-accts) (descendant-additions-subtractions acct accounts)
        ;; TODO: compute values for add/subtract and do the arithmetic
        (let
          ((acct-actual-val (gnc:get-single-account-periodlist-actual-value budget acct periodlist))
            (subtract-actual-offset-val
              (if selected-only?
                (apply +
                  (map
                    (lambda (sub-acct)
                      (gnc:get-single-account-periodlist-actual-value budget sub-acct periodlist))
                    subtract-accts))
                0))
            (add-actual-offset-val
              (if selected-only?
                (apply +
                  (map
                    (lambda (add-acct)
                      (gnc:get-single-account-periodlist-actual-value budget add-acct periodlist))
                    add-accts))
                0)))
            (+ (- acct-actual-val subtract-actual-offset-val) add-actual-offset-val))))

    ;; Adds a line to the budget report.
    ;;
    ;; Parameters:
    ;;   html-table - html table being created
    ;;   rownum - row number
    ;;   colnum - starting column number
    ;;   budget - budget to use
    ;;   acct - account being displayed
    ;;   exchange-fn - exchange function (not used)
    (define (gnc:html-table-add-budget-line!
             html-table rownum colnum budget acct
             column-list exchange-fn)
      (let* ((comm (xaccAccountGetCommodity acct))
             (reverse-balance? (gnc-reverse-balance acct))
             (maybe-negate (lambda (amt) (if reverse-balance? (- amt) amt)))
             (unreversed? (gnc-using-unreversed-budgets
                           (gnc-get-current-book))) ;fwd-compatibility
             (allperiods (filter number? (gnc:list-flatten column-list)))
             (total-periods (if (and accumulate? (not (null? allperiods)))
                                (iota (1+ (apply max allperiods)))
                                allperiods))
             (income-acct? (eqv? (xaccAccountGetType acct) ACCT-TYPE-INCOME)))

        ;; Displays a set of budget column values
        ;;
        ;; Parameters
        ;;   style-tag - cell style
        ;;   col - starting column to modify in html-table
        ;;   bgt-val - budget value
        ;;   act-val - actual value
        ;;   dif-val - difference value
        ;;   note    - note (string) or #f
        ;;
        ;; Returns
        ;;   col - next column
        (define (disp-cols style-tag col0
                           bgt-val act-val dif-val note)
          (let* ((col1 (+ col0 (if show-budget? 1 0)))
                 (col2 (+ col1 (if show-actual? 1 0)))
                 (col3 (+ col2 (if show-diff? 1 0))))
            (if show-budget?
                (gnc:html-table-set-cell/tag!
                 html-table rownum col0 style-tag
                 (if (zero? bgt-val) "."
                     (gnc:make-gnc-monetary comm bgt-val))
                 (if show-note? (footnotes note) "")))
            (if show-actual?
                (gnc:html-table-set-cell/tag!
                 html-table rownum col1
                 style-tag
                 (gnc:make-gnc-monetary comm act-val)))
            (if show-diff?
                (gnc:html-table-set-cell/tag!
                 html-table rownum col2
                 style-tag
                 (if (and (zero? bgt-val) (zero? act-val)) "."
                     (gnc:make-gnc-monetary comm dif-val))))
            col3))

        (let loop ((column-list column-list)
                   (current-col (1+ colnum)))
          (cond

           ((null? column-list)
            #f)

           ;; fwd-compatibility for unreversed budgets
           ((and (eq? (car column-list) 'total) unreversed?)
            (let* ((bgt-total (maybe-negate
                               (gnc:get-account-periodlist-budget-value
                                budget acct total-periods)))
                   (act-total (maybe-negate
                               (gnc:get-account-periodlist-actual-value
                                budget acct total-periods)))
                   (dif-total (- bgt-total act-total)))
              (loop (cdr column-list)
                    (disp-cols "total-number-cell" current-col
                               bgt-total act-total dif-total #f))))

           ((eq? (car column-list) 'total)
            (let* ((bgt-total (gnc:get-account-periodlist-budget-value
                               budget acct total-periods))
                   (act-total (gnc:get-account-periodlist-actual-value
                               budget acct total-periods))
                   (act-total (if reverse-balance? (- act-total) act-total))
                   (dif-total (if income-acct?
                                  (- act-total bgt-total)
                                  (- bgt-total act-total))))
              (loop (cdr column-list)
                    (disp-cols "total-number-cell" current-col
                               bgt-total act-total dif-total #f))))

           ;; fwd-compatibility for unreversed budgets
            ;; MY CHANGES to use rollover instead of accumulated
           (unreversed?
            (let* ((period-list (cond
                                 ((list? (car column-list)) (car column-list))
                                 (accumulate? (iota (1+ (car column-list))))
                                 (else (list (car column-list)))))
                   (period-list-prev (cond
                                       ((list? (car column-list)) (car column-list))
                                       (accumulate? (iota (car column-list)))
                                       (else '())))
                   (period-list-cur (cond
                                     ((list? (car column-list)) (car column-list))
                                     (else (list (car column-list)))))
                   (note (and (= 1 (length period-list))
                              (gnc-budget-get-account-period-note
                               budget acct (car period-list))))
                   ; TODO: fix for list types, e.g. when first column is a list of periods
                   (bgt-val-all (gnc:get-account-periodlist-budget-value
                                  budget acct period-list))
                   (act-val-prev (gnc:get-account-periodlist-actual-value
                                   budget acct period-list-prev))
                   (bgt-val (maybe-negate
                             (- bgt-val-all act-val-prev)
                             ))
                   ; (bgt-val (maybe-negate
                             ; (gnc:get-account-periodlist-budget-value
                              ; budget acct period-list)))
                   (act-val (maybe-negate
                             (gnc:get-account-periodlist-actual-value
                              budget acct period-list-cur)))
                   (dif-val (- bgt-val act-val)))
              (loop (cdr column-list)
                    (disp-cols "number-cell" current-col
                               bgt-val act-val dif-val note))))
          ; TODO: update this section as well!
           (else
            (let* ((period-list (cond
                                 ((list? (car column-list)) (car column-list))
                                 (accumulate? (iota (1+ (car column-list))))
                                 (else (list (car column-list)))))
                   (note (and (= 1 (length period-list))
                              (gnc-budget-get-account-period-note
                               budget acct (car period-list))))
                   (bgt-val (gnc:get-account-periodlist-budget-value
                             budget acct period-list))
                   (act-abs (gnc:get-account-periodlist-actual-value
                             budget acct period-list))
                   (act-val (if reverse-balance?
                                (- act-abs)
                                act-abs))
                   (dif-val (if income-acct?
                                (- act-val bgt-val)
                                (- bgt-val act-val))))
              (loop (cdr column-list)
                    (disp-cols "number-cell" current-col
                               bgt-val act-val dif-val note))))))))

    ;; Adds header rows to the budget report.  The columns are
    ;; specified by the column-list parameter.
    ;;
    ;; Parameters:
    ;;   html-table - html table being created
    ;;   colnum - starting column number
    ;;   budget - budget to use
    ;;   column-list - column info list
    (define (gnc:html-table-add-budget-headers!
             html-table colnum budget column-list)
      (let* ((current-col (1+ colnum))
             (col-span (max 1 (count identity
                                     (list show-budget? show-actual? show-diff?))))
             (period-to-date-string (lambda (p)
                                      (qof-print-date
                                       (gnc-budget-get-period-start-date budget p)))))

        ;; prepend 2 empty rows
        (gnc:html-table-prepend-row! html-table '())
        (gnc:html-table-prepend-row! html-table '())

        (let loop ((column-list column-list)
                   (current-col current-col))
          (unless (null? column-list)
            (gnc:html-table-set-cell!
             html-table 0 current-col
             (cond
              ((eq? (car column-list) 'total)
               (G_ "Total"))
              ((list? (car column-list))
               (format #f (G_ "~a to ~a")
                       (period-to-date-string (car (car column-list)))
                       (period-to-date-string (last (car column-list)))))
              (else
               (period-to-date-string (car column-list)))))

            (let ((tc (gnc:html-table-get-cell html-table 0 current-col)))
              (gnc:html-table-cell-set-colspan! tc col-span)
              (gnc:html-table-cell-set-tag! tc "centered-label-cell"))

            (loop (cdr column-list)
                  (1+ current-col))))

        ;; make the column headers
        (let loop ((column-list column-list)
                   (col0 current-col))
          (unless (null? column-list)
            (let* ((col1 (+ col0 (if show-budget? 1 0)))
                   (col2 (+ col1 (if show-actual? 1 0)))
                   (col3 (+ col2 (if show-diff? 1 0))))
              (when show-budget?
                (gnc:html-table-set-cell/tag!
                 html-table 1 col0 "centered-label-cell"
                 ;; Translators: Abbreviation for "Budget" amount
                 (G_ "Bgt")))
              (when show-actual?
                (gnc:html-table-set-cell/tag!
                 html-table 1 col1 "centered-label-cell"
                 ;; Translators: Abbreviation for "Actual" amount
                 (G_ "Act")))
              (when show-diff?
                (gnc:html-table-set-cell/tag!
                 html-table 1 col2 "centered-label-cell"
                 ;; Translators: Abbreviation for "Difference" amount
                 (G_ "Diff")))
              (loop (cdr column-list)
                    col3))))))

    ;; Determines the budget period relative to current period. Budget
    ;; period is current if it start time <= current time and end time
    ;; >= current time When period is found it's passed to adjuster
    ;; that is responsible for final calculation of period.
    ;;
    ;; If budget in future then first period of budget is returned,
    ;; if it in past, then the last period is returned if adjuster
    ;; produced period number that is less then first period or
    ;; greater than last period, the same rules apply.
    ;;
    ;; Parameters:
    ;;   budget - budget to use
    ;;   adjuster - function that is used for calculation of period relative to current
    (define (find-period-relative-to-current budget adjuster)
      (let* ((now (current-time))
             (total-periods (gnc-budget-get-num-periods budget))
             (last-period (1- total-periods))
             (period-start (lambda (x) (gnc-budget-get-period-start-date budget x)))
             (period-end (lambda (x) (gnc-budget-get-period-end-date budget x))))
        (cond ((< now (period-start 0)) 1)
              ((> now (period-end last-period)) total-periods)
              (else (let ((found-period
                           (find (lambda (period)
                                   (<= (period-start period)
                                       now
                                       (period-end period)))
                                 (iota total-periods))))
                      (and found-period
                           (max 0 (min last-period (adjuster found-period)))))))))
    ;; Maps type of user selected period to concrete period number, if
    ;; user not selected to use range false is returned
    (define (calc-user-period budget use-ranges? period-type period-exact-val)
      (and use-ranges?
           (case period-type
            ((first)    0)
            ((last)     (1- (gnc-budget-get-num-periods budget)))
            ((manual)   (1- period-exact-val))
            ((previous) (find-period-relative-to-current budget 1-))
            ((current)  (find-period-relative-to-current budget identity))
            ((next)     (find-period-relative-to-current budget 1+)))))
    ;; Performs calculation of periods list. If list element is a list
    ;; itself, it means that elements of this sublist should be
    ;; presented as summed value.  If user required a total column
    ;; calculation a quoted total val appended to the end For example
    ;; if function produced list ( (0 1 2 3 4) 5 6 7 (8 9) 'total)
    ;; then budget report will have 6 columns:
    ;; -- first column is a sum of values for periods 0..4
    ;; -- second .. forth columns is a values for periods 5,6,7
    ;; -- fifth is a sum of value for periods 8, 9
    ;; -- sixth a column with total of all columns
    ;;
    ;; Total is calculated only for selected periods. So if the list
    ;; resulted in (3 4 'total), total column will contain the sum of
    ;; values for periods 3,4
    (define (calc-periods
             budget user-start user-end collapse-before? collapse-after? show-total?)
      (define (range start end)
        (if (< start end)
            (iota (- end start) start)
            (iota (- start end) end)))
      (let* ((num-periods (gnc-budget-get-num-periods budget))
             (range-start (or user-start 0))
             (range-end (if user-end (1+ user-end) num-periods))
             (fold-before-start 0)
             (fold-before-end (if collapse-before? range-start 0))
             (fold-after-start (if collapse-after? range-end num-periods))
             (fold-after-end num-periods))
        (map (lambda (x) (if (and (list? x) (null? (cdr x))) (car x) x))
             (filter (lambda (x) (not (null? x)))
                     (append (list (range fold-before-start fold-before-end))
                             (range range-start range-end)
                             (list (range fold-after-start fold-after-end))
                             (if show-total? '(total) '()))))))
    ;; end of defines

    (let ((column-info-list (calc-periods
                             budget
                             (calc-user-period
                              budget use-ranges?
                              (get-val params 'user-start-period)
                              (get-val params 'user-start-period-exact))
                             (calc-user-period
                              budget use-ranges?
                              (get-val params 'user-end-period)
                              (get-val params 'user-end-period-exact))
                             (get-val params 'collapse-before)
                             (get-val params 'collapse-after)
                             show-totalcol?))
          ;;(html-table (or html-table (gnc:make-html-table)))
          ;; WARNING: we implicitly depend here on the details of
          ;; gnc:html-table-add-account-balances.  Specifically, we
          ;; assume that it makes twice as many columns as it uses for
          ;; account labels.  For now, that seems to be a valid
          ;; assumption.
          )
      ;;debug output for control of period list calculation
      (gnc:debug "use-ranges? =" use-ranges?)
      (gnc:debug "user-start-period =" (get-val params 'user-start-period))
      (gnc:debug "user-start-period-exact =" (get-val params 'user-start-period-exact))
      (gnc:debug "user-end-period =" (get-val params 'user-end-period))
      (gnc:debug "user-end-period-exact =" (get-val params 'user-end-period-exact))
      (gnc:debug "column-info-list=" column-info-list)

      ;; DEBUG LOG accounts
      (let ((num-rows (gnc:html-acct-table-num-rows acct-table)))
        (let loop ((rownum 0))
          (when (< rownum num-rows)
            (let* ((env (gnc:html-acct-table-get-row-env acct-table rownum))
                    (acct-name (get-val env 'account-name))
                    (acct-guid (get-val env 'account-guid))
                    (children (get-val env 'account-children))
                    (children-guids (if children
                                      (map (lambda (child) (gncAccountGetGUID child))
                                        children)
                                      '()))
                    (children-str (string-append "Account Children: (" (string-join children-guids ", ") ")"))
                    (debug-msg (string-append "Account Name: " acct-name ", Account GUID: " acct-guid
                                 ", " children-str)))
              (debug-log debug-msg))
            (loop (1+ rownum)))))


      ;; call gnc:html-table-add-budget-line! for each account
      (let loop ((rownum 0))
        (when (< rownum num-rows)
          (let* ((env (append (gnc:html-acct-table-get-row-env acct-table rownum)
                              params))
                 (acct (get-val env 'account))
                 (exchange-fn (get-val env 'exchange-fn)))
            (gnc:html-table-add-budget-line!
             html-table rownum colnum budget acct
             column-info-list exchange-fn)
            (loop (1+ rownum)))))

      ;; column headers
      (gnc:html-table-add-budget-headers!
       html-table colnum budget column-info-list))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; budget-renderer
;; set up the document and add the table
;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (budget-renderer report-obj)
  (define (get-option pagename optname)
    (get-option-val (gnc:report-options report-obj) pagename optname))

  (gnc:report-starting reportname)

  ;; get all option's values
  (let* ((budget (get-option gnc:pagename-general optname-budget))
         (budget-valid? (and budget (not (null? budget))))
         (display-depth (get-option gnc:pagename-accounts
                                    optname-display-depth))
         (show-subaccts? (get-option gnc:pagename-accounts
                                     optname-show-subaccounts))
         (accounts (get-option gnc:pagename-accounts
                               optname-accounts))
         (bottom-behavior (get-option gnc:pagename-accounts optname-bottom-behavior))
         (show-zb-accts? (get-option gnc:pagename-display
                                     optname-show-zb-accounts))
         (use-ranges? (get-option gnc:pagename-general optname-use-budget-period-range))
         (include-collapse-before? (and use-ranges?
                                        (get-option gnc:pagename-general
                                                    optname-period-collapse-before)))
         (include-collapse-after? (and use-ranges?
                                       (get-option gnc:pagename-general
                                                   optname-period-collapse-after)))
         (doc (gnc:make-html-document))
         (accounts (if show-subaccts?
                       (gnc:accounts-and-all-descendants accounts)
                       accounts)))
    ;; end of defines

    (cond

     ((null? accounts)
      ;; No accounts selected.
      (gnc:html-document-add-object!
       doc (gnc:html-make-no-account-warning reportname (gnc:report-id report-obj))))

     ((not budget-valid?)
      ;; No budget selected.
      (gnc:html-document-add-object!
       doc (gnc:html-make-generic-budget-warning reportname)))

     (else
      (let* ((tree-depth (if (eq? display-depth 'all)
                             (gnc:accounts-get-children-depth accounts)
                             display-depth))
             (to-period-val (lambda (v)
                              (inexact->exact
                               (truncate
                                (get-option gnc:pagename-general v)))))
             (env (list
                   (list 'start-date (gnc:budget-get-start-date budget))
                   (list 'end-date (gnc:budget-get-end-date budget))
                   (list 'display-tree-depth tree-depth)
                   (list 'depth-limit-behavior
                         (if bottom-behavior 'flatten 'summarize))
                   (list 'zero-balance-mode
                         (if show-zb-accts? 'show-leaf-acct 'omit-leaf-acct))
                   (list 'report-budget budget)))
             (accounts (sort accounts gnc:account-full-name<?))
             (accumulate? (get-option gnc:pagename-general optname-accumulate))
             (acct-table (gnc:make-html-acct-table/env/accts env accounts))
             (footnotes (make-footnote-collector))
             (paramsBudget
              (list
               (list 'show-actual
                     (get-option gnc:pagename-display optname-show-actual))
               (list 'show-budget
                     (get-option gnc:pagename-display optname-show-budget))
               (list 'show-difference
                     (get-option gnc:pagename-display optname-show-difference))
               (list 'show-note
                     (and (get-option gnc:pagename-display optname-show-budget)
                          (get-option gnc:pagename-display optname-show-notes)))
               (list 'footnotes footnotes)
               (list 'use-envelope accumulate?)
               (list 'show-totalcol
                     (get-option gnc:pagename-display optname-show-totalcol))
               (list 'use-ranges use-ranges?)
               (list 'collapse-before include-collapse-before?)
               (list 'collapse-after include-collapse-after?)
               (list 'user-start-period
                     (get-option gnc:pagename-general
                                 optname-budget-period-start))
               (list 'user-end-period
                     (get-option gnc:pagename-general
                                 optname-budget-period-end))
               (list 'user-start-period-exact
                     (to-period-val optname-budget-period-start-exact))
               (list 'user-end-period-exact
                     (to-period-val optname-budget-period-end-exact))
               (list 'accounts accounts)
               (list 'selected-only (get-option gnc:pagename-general optname-selected-only))))
             (report-name (get-option gnc:pagename-general
                                      gnc:optname-reportname)))

        (gnc:html-document-set-title!
         doc (format #f "~a: ~a ~a"
                     report-name (gnc-budget-get-name budget)
                     ;; Translators: using accumulated amounts mean
                     ;; budget will report on budgeted and actual
                     ;; amounts from the beginning of budget, instead
                     ;; of only using the budget-period amounts.
                     (if accumulate? (G_ "using accumulated amounts")
                         "")))

        ;; We do this in two steps: First the account names...  the
        ;; add-account-balances will actually compute and add a
        ;; bunch of current account balances, too, but we'll
        ;; overwrite them.
        (let ((html-table (gnc:html-table-add-account-balances #f acct-table '())))

          ;; ... then the budget values
          (gnc:html-table-add-budget-values! html-table acct-table budget paramsBudget)

          ;; hmmm... I expected that add-budget-values would have to
          ;; clear out any unused columns to the right, out to the
          ;; table width, since the add-account-balance had put stuff
          ;; there, but it doesn't seem to matter.

          (gnc:html-table-set-style!
           html-table "td"
           'attribute '("valign" "bottom"))

          (gnc:html-document-add-object! doc html-table)

          (gnc:html-document-add-object! doc (footnotes 'list))))))

    (gnc:report-finished)
    doc))

(gnc:define-report
 'version 1.1
 'name reportname
 'report-guid "c92dbaf448af48339edb31f14e5b3892"
 'menu-path (list gnc:menuname-budget)
 'options-generator budget-report-options-generator
 'renderer budget-renderer)
