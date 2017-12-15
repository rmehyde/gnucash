;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; transaction-report.scm : Report on all transactions in account(s)
;;
;; Original report by Robert Merkel <rgmerk@mira.net>
;; Contributions by Bryan Larsen <blarsen@ada-works.com>
;; More contributions for new report generation code by Robert Merkel
;; More contributions by Christian Stimming <stimming@tuhh.de>
;; Modified to support the intersection of two account lists by
;; Michael T. Garrison Stuber
;; Modified account names display by Tomas Pospisek
;; <tpo_deb@sourcepole.ch> with a lot of help from "warlord"
;; Refactored by Christopher Lam (2017)
;; - introduced account/transaction substring/regex matcher
;; - add custom sorter in scheme
;; - common currency - optionally show original currency amount
;;   and enable multiple data columns
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

(define-module (gnucash report standard-reports transaction))

(use-modules (gnucash main)) ;; FIXME: delete after we finish modularizing.
(use-modules (srfi srfi-1))
(use-modules (srfi srfi-13))
(use-modules (ice-9 regex))
(use-modules (gnucash gnc-module))
(use-modules (gnucash gettext))
(use-modules (gnucash printf))

(gnc:module-load "gnucash/report/report-system" 0)

(define-macro (addto! alist element)
  `(set! ,alist (cons ,element ,alist)))

;; Define the strings here to avoid typos and make changes easier.
(define reportname (N_ "Transaction Report"))

;;Accounts
(define optname-accounts (N_ "Accounts"))
(define optname-filterby (N_ "Filter By..."))
(define optname-filtertype (N_ "Filter Type"))
(define optname-void-transactions (N_ "Void Transactions"))

;;Display
(define optname-detail-level (N_ "Detail Level"))

;;Sorting
(define pagename-sorting (N_ "Sorting"))
(define optname-prime-sortkey (N_ "Primary Key"))
(define optname-prime-subtotal (N_ "Primary Subtotal"))
(define optname-prime-sortorder (N_ "Primary Sort Order"))
(define optname-prime-date-subtotal (N_ "Primary Subtotal for Date Key"))
(define optname-full-account-name (N_ "Show Full Account Name"))
(define optname-show-account-code (N_ "Show Account Code"))
(define optname-show-account-description (N_ "Show Account Description"))
(define optname-sec-sortkey (N_ "Secondary Key"))
(define optname-sec-subtotal (N_ "Secondary Subtotal"))
(define optname-sec-sortorder  (N_ "Secondary Sort Order"))
(define optname-sec-date-subtotal (N_ "Secondary Subtotal for Date Key"))

;;General
(define optname-startdate (N_ "Start Date"))
(define optname-enddate (N_ "End Date"))
(define optname-table-export (N_ "Table for Exporting"))
(define optname-common-currency (N_ "Common Currency"))
(define optname-orig-currency (N_ "Show original currency amount"))
(define optname-currency (N_ "Report's currency"))

;;Filtering
(define pagename-filter (N_ "Filter"))
(define optname-account-matcher (N_ "Account Matcher"))
(define optname-account-matcher-regex (N_ "Account Matcher uses regular expressions for extended matching"))
(define optname-transaction-matcher (N_ "Transaction Matcher"))
(define optname-transaction-matcher-regex (N_ "Transaction Matcher uses regular expressions for extended matching"))
(define optname-reconcile-status (N_ "Reconcile Status"))

;;Styles
(define def:grand-total-style "grand-total")
(define def:normal-row-style "normal-row")
(define def:alternate-row-style "alternate-row")
(define def:primary-subtotal-style "primary-subheading")
(define def:secondary-subtotal-style "secondary-subheading")

(define NO-MATCHING-TRANS-HEADER (_ "No matching transactions found"))
(define NO-MATCHING-TRANS-TEXT (_ "No transactions were found that \
match the time interval and account selection specified \
in the Options panel."))
(define NO-MATCHING-ACCT-HEADER (N_ "No matching accounts found"))
(define NO-MATCHING-ACCT-TEXT (N_ "No account were found that match the \
options specified in the Options panels."))


(define DATE-SORTING-TYPES (list 'date 'reconciled-date))

;; The option-values of the sorting key multichoice option, for
;; which a subtotal should be enabled.
(define SUBTOTAL-ENABLED (list 'account-name 'corresponding-acc-name
                               'account-code 'corresponding-acc-code))


(define sortkey-list
  ;;
  ;; Defines the different sorting keys, as an association-list
  ;; together with the subtotal functions. Each entry:
  ;;  'sortkey             - sort parameter sent via qof-query
  ;;  'split-sortvalue     - function which retrieves number/string used for comparing splits
  ;;  'text                - text displayed in Display tab
  ;;  'tip                 - tooltip displayed in Display tab
  ;;  'renderer-key        - helper symbol to select subtotal/subheading renderer
  ;;
  (list (cons 'account-name  (list (cons 'sortkey (list SPLIT-ACCT-FULLNAME))
                                   (cons 'split-sortvalue (lambda (a) (gnc-account-get-full-name (xaccSplitGetAccount a))))
                                   (cons 'text (N_ "Account Name"))
                                   (cons 'tip (N_ "Sort & subtotal by account name."))
                                   (cons 'renderer-key 'account)))

        (cons 'account-code (list (cons 'sortkey (list SPLIT-ACCOUNT ACCOUNT-CODE-))
                                  (cons 'split-sortvalue (lambda (a) (xaccAccountGetCode (xaccSplitGetAccount a))))
                                  (cons 'text (N_ "Account Code"))
                                  (cons 'tip (N_ "Sort & subtotal by account code."))
                                  (cons 'renderer-key 'account)))

        (cons 'date         (list (cons 'sortkey (list SPLIT-TRANS TRANS-DATE-POSTED))
                                  (cons 'split-sortvalue #f)
                                  (cons 'text (N_ "Date"))
                                  (cons 'tip (N_ "Sort by date."))
                                  (cons 'renderer-key #f)))

        (cons 'reconciled-date (list (cons 'sortkey (list SPLIT-DATE-RECONCILED))
                                     (cons 'split-sortvalue #f)
                                     (cons 'text (N_ "Reconciled Date"))
                                     (cons 'tip (N_ "Sort by the Reconciled Date."))
                                     (cons 'renderer-key #f)))

        (cons 'register-order (list (cons 'sortkey (list QUERY-DEFAULT-SORT))
                                    (cons 'split-sortvalue #f)
                                    (cons 'text (N_ "Register Order"))
                                    (cons 'tip (N_ "Sort as in the register."))
                                    (cons 'renderer-key #f)))

        (cons 'corresponding-acc-name (list (cons 'sortkey (list SPLIT-CORR-ACCT-NAME))
                                            (cons 'split-sortvalue (lambda (a) (xaccSplitGetCorrAccountFullName a)))
                                            (cons 'text (N_ "Other Account Name"))
                                            (cons 'tip (N_ "Sort by account transferred from/to's name."))
                                            (cons 'renderer-key 'other-acc)))

        (cons 'corresponding-acc-code (list (cons 'sortkey (list SPLIT-CORR-ACCT-CODE))
                                            (cons 'split-sortvalue (lambda (a) (xaccSplitGetCorrAccountCode a)))
                                            (cons 'text (N_ "Other Account Code"))
                                            (cons 'tip (N_ "Sort by account transferred from/to's code."))
                                            (cons 'renderer-key 'other-acct)))

        (cons 'amount        (list (cons 'sortkey (list SPLIT-VALUE))
                                   (cons 'split-sortvalue #f)
                                   (cons 'text (N_ "Amount"))
                                   (cons 'tip (N_ "Sort by amount."))
                                   (cons 'renderer-key #f)))

        (cons 'description   (list (cons 'sortkey (list SPLIT-TRANS TRANS-DESCRIPTION))
                                   (cons 'split-sortvalue #f)
                                   (cons 'text (N_ "Description"))
                                   (cons 'tip (N_ "Sort by description."))
                                   (cons 'renderer-key #f)))

        (if (qof-book-use-split-action-for-num-field (gnc-get-current-book))
            (cons 'number    (list (cons 'sortkey (list SPLIT-ACTION))
                                   (cons 'split-sortvalue #f)
                                   (cons 'text (N_ "Number/Action"))
                                   (cons 'tip (N_ "Sort by check number/action."))
                                   (cons 'renderer-key #f)))

            (cons 'number    (list (cons 'sortkey (list SPLIT-TRANS TRANS-NUM))
                                   (cons 'split-sortvalue #f)
                                   (cons 'text (N_ "Number"))
                                   (cons 'tip (N_ "Sort by check/transaction number."))
                                   (cons 'renderer-key #f))))

        (cons 't-number      (list (cons 'sortkey (list SPLIT-TRANS TRANS-NUM))
                                   (cons 'split-sortvalue #f)
                                   (cons 'text (N_ "Transaction Number"))
                                   (cons 'tip (N_ "Sort by transaction number."))
                                   (cons 'renderer-key #f)))

        (cons 'memo          (list (cons 'sortkey (list SPLIT-MEMO))
                                   (cons 'split-sortvalue #f)
                                   (cons 'text (N_ "Memo"))
                                   (cons 'tip (N_ "Sort by memo."))
                                   (cons 'renderer-key #f)))

        (cons 'none          (list (cons 'sortkey '())
                                   (cons 'split-sortvalue #f)
                                   (cons 'text (N_ "None"))
                                   (cons 'tip (N_ "Do not sort."))
                                   (cons 'renderer-key #f)))))


(define (sortkey-get-info sortkey info)
  (cdr (assq info (cdr (assq sortkey sortkey-list)))))

(define (timepair-year tp)    (gnc:timepair-get-year tp))
(define (timepair-quarter tp) (+ (* 10 (timepair-year tp))  (gnc:timepair-get-quarter tp)))
(define (timepair-month tp)   (+ (* 100 (timepair-year tp)) (gnc:timepair-get-month tp)))
(define (timepair-week tp)    (+ (* 100 (timepair-year tp)) (gnc:timepair-get-week tp)))
(define (split-week a) (timepair-week (gnc-transaction-get-date-posted (xaccSplitGetParent a))))
(define (split-month a) (timepair-month (gnc-transaction-get-date-posted (xaccSplitGetParent a))))
(define (split-quarter a) (timepair-quarter (gnc-transaction-get-date-posted (xaccSplitGetParent a))))
(define (split-year a) (timepair-year (gnc-transaction-get-date-posted (xaccSplitGetParent a))))

(define date-subtotal-list
  ;; List for date option.
  ;; Defines the different date sorting keys, as an association-list. Each entry:
  ;;  'split-sortvalue     - function which retrieves number/string used for comparing splits
  ;;  'text                - text displayed in Display tab
  ;;  'tip                 - tooltip displayed in Display tab
  ;;  'renderer-key        - helper symbol to select subtotal/subheading renderer
  (list
   (cons 'none (list
                (cons 'split-sortvalue #f)
                (cons 'text (N_ "None"))
                (cons 'tip (N_ "None."))
                (cons 'renderer-key #f)))

   (cons 'weekly (list
                  (cons 'split-sortvalue split-week)
                  (cons 'text (N_ "Weekly"))
                  (cons 'tip (N_ "Weekly."))
                  (cons 'renderer-key 'week)))

   (cons 'monthly (list
                   (cons 'split-sortvalue split-month)
                   (cons 'text (N_ "Monthly"))
                   (cons 'tip (N_ "Monthly."))
                   (cons 'renderer-key 'month)))

   (cons 'quarterly (list
                     (cons 'split-sortvalue split-quarter)
                     (cons 'text (N_ "Quarterly"))
                     (cons 'tip (N_ "Quarterly."))
                     (cons 'renderer-key 'quarter)))

   (cons 'yearly (list
                  (cons 'split-sortvalue split-year)
                  (cons 'text (N_ "Yearly"))
                  (cons 'tip (N_ "Yearly."))
                  (cons 'renderer-key 'year)))))

(define (date-subtotal-get-info sortkey info)
  (cdr (assq info (cdr (assq sortkey date-subtotal-list)))))


(define (trep-options-generator)

  (define options (gnc:new-options))
  (define BOOK-SPLIT-ACTION (qof-book-use-split-action-for-num-field (gnc-get-current-book)))
  (define (gnc:register-trep-option new-option)
    (gnc:register-option options new-option))

  ;; General options

  (gnc:options-add-date-interval!
   options gnc:pagename-general optname-startdate optname-enddate "a")

  (gnc:register-trep-option
   (gnc:make-complex-boolean-option
    gnc:pagename-general optname-common-currency
    "e" (N_ "Convert all transactions into a common currency.") #f
    #f
    (lambda (x)
      (begin
        (gnc-option-db-set-option-selectable-by-name options
                                                     gnc:pagename-general
                                                     optname-currency x)
        (gnc-option-db-set-option-selectable-by-name options
                                                     gnc:pagename-general
                                                     optname-orig-currency x)))))

  (gnc:options-add-currency!
   options gnc:pagename-general optname-currency "f")

  (gnc:register-trep-option
   (gnc:make-simple-boolean-option
    gnc:pagename-general optname-orig-currency
    "f1" (N_ "Also show original currency amounts") #f))

  (gnc:register-trep-option
   (gnc:make-simple-boolean-option
    gnc:pagename-general optname-table-export
    "g" (N_ "Formats the table suitable for cut & paste exporting with extra cells.") #f))

  ;; Filtering Options

  (gnc:register-trep-option
   (gnc:make-string-option
    pagename-filter optname-account-matcher
    "a5" (N_ "Match only accounts whose fullname is matched e.g. ':Travel' will match \
Expenses:Travel:Holiday and Expenses:Business:Travel. It can be left blank, which will \
disable the matcher.")
    ""))

  (gnc:register-trep-option
   (gnc:make-simple-boolean-option
    pagename-filter optname-account-matcher-regex
    "a6"
    (N_ "By default the account matcher will search substring only. Set this to true to \
enable full POSIX regular expressions capabilities. 'Car|Flights' will match both \
Expenses:Car and Expenses:Flights. Use a period (.) to match a single character e.g. \
'20../.' will match 'Travel 2017/1 London'. ")
    #f))

  (gnc:register-trep-option
   (gnc:make-string-option
    pagename-filter optname-transaction-matcher
    "i1" (N_ "Match only transactions whose substring is matched e.g. '#gift' \
will find all transactions with #gift in description, notes or memo. It can be left \
blank, which will disable the matcher.")
    ""))

  (gnc:register-trep-option
   (gnc:make-simple-boolean-option
    pagename-filter optname-transaction-matcher-regex
    "i2"
    (N_ "By default the transaction matcher will search substring only. Set this to true to \
enable full POSIX regular expressions capabilities. '#work|#family' will match both \
tags within description, notes or memo. ")
    #f))

  (gnc:register-trep-option
   (gnc:make-multichoice-option
    pagename-filter optname-reconcile-status
    "j1" (N_ "Filter by reconcile status.")
    #f
    (list (vector #f      (N_ "All")           (N_ "Show All Transactions"))
          (vector '(#\n)  (N_ "Unreconciled")  (N_ "Unreconciled only"))
          (vector '(#\c)  (N_ "Cleared")       (N_ "Cleared only"))
          (vector '(#\y)  (N_ "Reconciled")    (N_ "Reconciled only")))))

  ;; Accounts options

  ;; account to do report on
  (gnc:register-trep-option
   (gnc:make-account-list-option
    gnc:pagename-accounts optname-accounts
    "a" (N_ "Report on these accounts.")
    ;; select, by default, no accounts! Selecting all accounts will
    ;; always imply an insanely long waiting time upon opening, and it
    ;; is almost never useful. So we instead display the normal error
    ;; message saying "Click here", and the user knows how to
    ;; continue.
    (lambda ()
      '())
    #f #t))

  (gnc:register-trep-option
   (gnc:make-account-list-option
    gnc:pagename-accounts optname-filterby
    "b" (N_ "Filter on these accounts.")
    (lambda ()
      '())
    #f #t))

  (gnc:register-trep-option
   (gnc:make-multichoice-option
    gnc:pagename-accounts optname-filtertype
    "c" (N_ "Filter account.")
    'none
    (list (vector 'none
                  (N_ "None")
                  (N_ "Do not do any filtering."))
          (vector 'include
                  (N_ "Include Transactions to/from Filter Accounts")
                  (N_ "Include transactions to/from filter accounts only."))
          (vector 'exclude
                  (N_ "Exclude Transactions to/from Filter Accounts")
                  (N_ "Exclude transactions to/from all filter accounts.")))))
  ;;

  (gnc:register-trep-option
   (gnc:make-multichoice-option
    gnc:pagename-accounts optname-void-transactions
    "d" (N_ "How to handle void transactions.")
    'non-void-only
    (list
     (vector 'non-void-only (N_ "Non-void only") (N_ "Show only non-voided transactions."))
     (vector 'void-only     (N_ "Void only") (N_ "Show only voided transactions."))
     (vector 'both          (N_ "Both") (N_ "Show both (and include void transactions in totals).")))))

  ;; Sorting options
  

  (let ((ascending-choice-list 
         (list (vector 'ascend
                       (N_ "Ascending")
                       (N_ "Smallest to largest, earliest to latest."))
               (vector 'descend
                       (N_ "Descending")
                       (N_ "Largest to smallest, latest to earliest."))))
        (prime-sortkey 'account-name)
        (prime-sortkey-subtotal-true #t)
        (sec-sortkey 'register-order)
        (sec-sortkey-subtotal-true #f)       
        (key-choice-list (map
                          (lambda (sortpair)
                            (vector
                             (car sortpair)
                             (sortkey-get-info (car sortpair) 'text)
                             (sortkey-get-info (car sortpair) 'tip)))
                          sortkey-list))
        (date-subtotal-choice-list (map
                                    (lambda (date-sortpair)
                                      (vector
                                       (car date-sortpair)
                                       (date-subtotal-get-info (car date-sortpair) 'text)
                                       (date-subtotal-get-info (car date-sortpair) 'tip)))
                                    date-subtotal-list)))

    (define (apply-selectable-by-name-sorting-options)
      (let* ((prime-sortkey-enabled (not (eq? prime-sortkey 'none)))
             (prime-sortkey-subtotal-enabled (member prime-sortkey SUBTOTAL-ENABLED))
             (prime-date-sortingtype-enabled (member prime-sortkey DATE-SORTING-TYPES))
             (sec-sortkey-enabled (not (eq? sec-sortkey 'none)))
             (sec-sortkey-subtotal-enabled (member sec-sortkey SUBTOTAL-ENABLED))
             (sec-date-sortingtype-enabled (member sec-sortkey DATE-SORTING-TYPES)))

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-prime-subtotal
         prime-sortkey-subtotal-enabled)

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-prime-sortorder
         prime-sortkey-enabled)

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-sec-subtotal
         sec-sortkey-subtotal-enabled)

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-sec-sortorder
         sec-sortkey-enabled)

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-full-account-name
         (or (and prime-sortkey-subtotal-enabled prime-sortkey-subtotal-true)
             (and sec-sortkey-subtotal-enabled sec-sortkey-subtotal-true)))

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-show-account-code
         (or (and prime-sortkey-subtotal-enabled prime-sortkey-subtotal-true)
             (and sec-sortkey-subtotal-enabled sec-sortkey-subtotal-true)))

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-show-account-description
         (or (and prime-sortkey-subtotal-enabled prime-sortkey-subtotal-true)
             (and sec-sortkey-subtotal-enabled sec-sortkey-subtotal-true)))

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-prime-date-subtotal
         prime-date-sortingtype-enabled)

        (gnc-option-db-set-option-selectable-by-name
         options pagename-sorting optname-sec-date-subtotal
         sec-date-sortingtype-enabled)))

    ;; primary sorting criterion
    (gnc:register-trep-option
     (gnc:make-multichoice-callback-option
      pagename-sorting optname-prime-sortkey
      "a" (N_ "Sort by this criterion first.")
      prime-sortkey
      key-choice-list #f
      (lambda (x)
        (set! prime-sortkey x)
        (apply-selectable-by-name-sorting-options))))

    (gnc:register-trep-option
     (gnc:make-simple-boolean-option
      pagename-sorting optname-full-account-name
      "j1"
      (N_ "Show the full account name for subtotals and subheadings?")
      #f))

    (gnc:register-trep-option
     (gnc:make-simple-boolean-option
      pagename-sorting optname-show-account-code
      "j2"
      (N_ "Show the account code for subtotals and subheadings?")
      #f))

    (gnc:register-trep-option
     (gnc:make-simple-boolean-option
      pagename-sorting optname-show-account-description
      "j3"
      (N_ "Show the account description for subheadings?")
      #f))
    
    (gnc:register-trep-option
     (gnc:make-complex-boolean-option
      pagename-sorting optname-prime-subtotal
      "e5"
      (N_ "Subtotal according to the primary key?")
      prime-sortkey-subtotal-true #f
      (lambda (x)
        (set! prime-sortkey-subtotal-true x)
        (apply-selectable-by-name-sorting-options))))

    (gnc:register-trep-option
     (gnc:make-multichoice-option
      pagename-sorting optname-prime-date-subtotal
      "e2" (N_ "Do a date subtotal.")
      'monthly
      date-subtotal-choice-list))

    (gnc:register-trep-option
     (gnc:make-multichoice-option
      pagename-sorting optname-prime-sortorder
      "e" (N_ "Order of primary sorting.")
      'ascend
      ascending-choice-list))

    ;; Secondary sorting criterion
    (gnc:register-trep-option
     (gnc:make-multichoice-callback-option
      pagename-sorting optname-sec-sortkey
      "f"
      (N_ "Sort by this criterion second.")
      sec-sortkey
      key-choice-list #f
      (lambda (x)
        (set! sec-sortkey x)
        (apply-selectable-by-name-sorting-options))))

    (gnc:register-trep-option
     (gnc:make-complex-boolean-option
      pagename-sorting optname-sec-subtotal
      "i5"
      (N_ "Subtotal according to the secondary key?")
      sec-sortkey-subtotal-true #f
      (lambda (x)
        (set! sec-sortkey-subtotal-true x)
        (apply-selectable-by-name-sorting-options))))

    (gnc:register-trep-option
     (gnc:make-multichoice-option
      pagename-sorting optname-sec-date-subtotal
      "i2" (N_ "Do a date subtotal.")
      'monthly
      date-subtotal-choice-list))

    (gnc:register-trep-option
     (gnc:make-multichoice-option
      pagename-sorting optname-sec-sortorder
      "i" (N_ "Order of Secondary sorting.")
      'ascend
      ascending-choice-list)))

  ;; Display options

  (let ((disp-memo? #t)
        (disp-accname? #t)
        (disp-other-accname? #f)
        (is-single? #t))

    (define (apply-selectable-by-name-display-options)
      (gnc-option-db-set-option-selectable-by-name
       options gnc:pagename-display (N_ "Use Full Account Name")
       disp-accname?)

      (gnc-option-db-set-option-selectable-by-name
       options gnc:pagename-display (N_ "Other Account Name")
       is-single?)

      (gnc-option-db-set-option-selectable-by-name
       options gnc:pagename-display (N_ "Use Full Other Account Name")
       (and disp-other-accname? is-single?))

      (gnc-option-db-set-option-selectable-by-name
       options gnc:pagename-display (N_ "Other Account Code")
       is-single?)

      (gnc-option-db-set-option-selectable-by-name
       options gnc:pagename-display (N_ "Notes")
       disp-memo?))

    (for-each
     (lambda (l)
       (gnc:register-trep-option
        (gnc:make-simple-boolean-option
         gnc:pagename-display (car l) (cadr l) (caddr l) (cadddr l))))
     ;; One list per option here with: option-name, sort-tag,
     ;; help-string, default-value
     (list
      (list (N_ "Date")                         "a"  (N_ "Display the date?") #t)
      (list (N_ "Reconciled Date")              "a2" (N_ "Display the reconciled date?") #f)
      (if BOOK-SPLIT-ACTION
          (list (N_ "Num/Action")               "b"  (N_ "Display the check number?") #t)
          (list (N_ "Num")                      "b"  (N_ "Display the check number?") #t))
      (list (N_ "Description")                  "c"  (N_ "Display the description?") #t)
      (list (N_ "Notes")                        "d2" (N_ "Display the notes if the memo is unavailable?") #t)
      ;; account name option appears here
      (list (N_ "Use Full Account Name")        "f"  (N_ "Display the full account name?") #t)
      (list (N_ "Account Code")                 "g"  (N_ "Display the account code?") #f)
      ;; other account name option appears here
      (list (N_ "Use Full Other Account Name")  "i"  (N_ "Display the full account name?") #f)
      (list (N_ "Other Account Code")           "j"  (N_ "Display the other account code?") #f)
      (list (N_ "Shares")                       "k"  (N_ "Display the number of shares?") #f)
      (list (N_ "Price")                        "l"  (N_ "Display the shares price?") #f)
      ;; note the "Amount" multichoice option in between here
      (list (N_ "Running Balance")              "n"  (N_ "Display a running balance?") #f)
      (list (N_ "Totals")                       "o"  (N_ "Display the totals?") #t)))

    (if BOOK-SPLIT-ACTION
        (gnc:register-trep-option
         (gnc:make-simple-boolean-option
          gnc:pagename-display (N_ "Trans Number")
          "b2" (N_ "Display the trans number?") #f)))

    ;; Add an option to display the memo, and disable the notes option
    ;; when memos are not included.
    (gnc:register-trep-option
     (gnc:make-complex-boolean-option
      gnc:pagename-display (N_ "Memo")
      "d"  (N_ "Display the memo?") #t
      disp-memo?
      (lambda (x)
        (set! disp-memo? x)
        (apply-selectable-by-name-display-options))))

    ;; Ditto for Account Name #t -> Use Full Account Name is selectable
    (gnc:register-trep-option
     (gnc:make-complex-boolean-option
      gnc:pagename-display (N_ "Account Name")
      "e"  (N_ "Display the account name?") #t
      disp-accname?
      (lambda (x)
        (set! disp-accname? x)
        (apply-selectable-by-name-display-options))))

    ;; Ditto for Other Account Name #t -> Use Full Other Account Name is selectable
    (gnc:register-trep-option
     (gnc:make-complex-boolean-option
      gnc:pagename-display (N_ "Other Account Name")
      "h5"  (N_ "Display the other account name? (if this is a split transaction, this parameter is guessed).") #f
      disp-other-accname?
      (lambda (x)
        (set! disp-other-accname? x)
        (apply-selectable-by-name-display-options))))

    (gnc:register-trep-option
     (gnc:make-multichoice-callback-option
      gnc:pagename-display optname-detail-level
      "h" (N_ "Amount of detail to display per transaction.")
      'single
      (list (vector 'multi-line
                    (N_ "Multi-Line")
                    (N_ "Display all splits in a transaction on a separate line."))
            (vector 'single
                    (N_ "Single")
                    (N_ "Display one line per transaction, merging multiple splits where required.")))
      #f
      (lambda (x)
        (set! is-single? (eq? x 'single))
        (apply-selectable-by-name-display-options))))

    (gnc:register-trep-option
     (gnc:make-multichoice-option
      gnc:pagename-display (N_ "Amount")
      "m" (N_ "Display the amount?")
      'single
      (list
       (vector 'none   (N_ "None") (N_ "No amount display."))
       (vector 'single (N_ "Single") (N_ "Single Column Display."))
       (vector 'double (N_ "Double") (N_ "Two Column Display.")))))

    (gnc:register-trep-option
     (gnc:make-multichoice-option
      gnc:pagename-display (N_ "Sign Reverses")
      "p" (N_ "Reverse amount display for certain account types.")
      'credit-accounts
      (list (vector 'none
                    (N_ "None")
                    (N_ "Don't change any displayed amounts."))
            (vector 'income-expense
                    (N_ "Income and Expense")
                    (N_ "Reverse amount display for Income and Expense Accounts."))
            (vector 'credit-accounts
                    (N_ "Credit Accounts")
                    (N_ "Reverse amount display for Liability, Payable, Equity, \
Credit Card, and Income accounts."))))))

  (gnc:options-set-default-section options gnc:pagename-general)
  options)

;; ;;;;;;;;;;;;;;;;;;;;
;; Here comes the big function that builds the whole table.

(define (make-split-table splits options
                          primary-subtotal-comparator
                          secondary-subtotal-comparator
                          primary-renderer-key
                          secondary-renderer-key)

  (define (opt-val section name) (gnc:option-value (gnc:lookup-option options section name)))
  (define BOOK-SPLIT-ACTION (qof-book-use-split-action-for-num-field (gnc-get-current-book)))

  (define (build-columns-used)
    (define is-single? (eq? (opt-val gnc:pagename-display optname-detail-level) 'single))
    (define amount-setting (opt-val gnc:pagename-display (N_ "Amount")))
    (list (cons 'date (opt-val gnc:pagename-display (N_ "Date")))
          (cons 'reconciled-date (opt-val gnc:pagename-display (N_ "Reconciled Date")))
          (cons 'num (if BOOK-SPLIT-ACTION
                         (opt-val gnc:pagename-display (N_ "Num/Action"))
                         (opt-val gnc:pagename-display (N_ "Num"))))
          (cons 'description (opt-val gnc:pagename-display (N_ "Description")))
          (cons 'account-name (opt-val gnc:pagename-display (N_ "Account Name")))
          (cons 'other-account-name (and is-single?
                                         (opt-val gnc:pagename-display (N_ "Other Account Name"))))
          (cons 'shares (opt-val gnc:pagename-display (N_ "Shares")))
          (cons 'price (opt-val gnc:pagename-display (N_ "Price")))
          (cons 'amount-single (eq? amount-setting 'single))
          (cons 'amount-double (eq? amount-setting 'double))
          (cons 'amount-original-currency
                (and (opt-val gnc:pagename-general optname-common-currency)
                     (opt-val gnc:pagename-general optname-orig-currency)))
          (cons 'running-balance (opt-val gnc:pagename-display (N_ "Running Balance")))
          (cons 'account-full-name (opt-val gnc:pagename-display (N_ "Use Full Account Name")))
          (cons 'memo (opt-val gnc:pagename-display (N_ "Memo")))
          (cons 'account-code (opt-val gnc:pagename-display (N_ "Account Code")))
          (cons 'other-account-code (and is-single?
                                         (opt-val gnc:pagename-display (N_ "Other Account Code"))))
          (cons 'other-account-full-name (and is-single?
                                              (opt-val gnc:pagename-display (N_ "Use Full Other Account Name"))))
          (cons 'sort-account-code (opt-val pagename-sorting (N_ "Show Account Code")))
          (cons 'sort-account-full-name (opt-val pagename-sorting (N_ "Show Full Account Name")))
          (cons 'sort-account-description (opt-val pagename-sorting (N_ "Show Account Description")))
          (cons 'notes (opt-val gnc:pagename-display (N_ "Notes")))))

  (define (column-uses? param columns-used)
    (cdr (assq param columns-used)))

  (define (make-heading-list columns-used)
    (define (add-if pred? . items) (if pred? items '()))
    (append
     (add-if (column-uses? 'date columns-used)
             (_ "Date"))
     (add-if (column-uses? 'reconciled-date columns-used)
             (_ "Reconciled Date"))
     (add-if (column-uses? 'num columns-used)
             (if (and (qof-book-use-split-action-for-num-field (gnc-get-current-book))
                      (opt-val gnc:pagename-display (N_ "Trans Number")))
                 (_ "Num/T-Num")
                 (_ "Num")))
     (add-if (column-uses? 'description columns-used)
             (_ "Description"))
     (add-if (column-uses? 'memo columns-used)
             (if (column-uses? 'notes columns-used)
                 (string-append (_ "Memo") "/" (_ "Notes"))
                 (_ "Memo")))
     (add-if (or (column-uses? 'account-name columns-used)
                 (column-uses? 'account-code columns-used))
             (_ "Account"))
     (add-if (or (column-uses? 'other-account-name columns-used)
                 (column-uses? 'other-account-code columns-used))
             (_ "Transfer from/to"))
     (add-if (column-uses? 'shares columns-used)
             (_ "Shares"))
     (add-if (column-uses? 'price columns-used)
             (_ "Price"))))

  (define (make-amount-heading-list columns-used)
    (define (add-if pred? . items) (if pred? items '()))
    (append
     (add-if (column-uses? 'amount-single columns-used)
             (_ "Amount"))
     ;; FIXME: Proper labels: what?
     (add-if (column-uses? 'amount-double columns-used)
             (_ "Debit")
             (_ "Credit"))
     (add-if (column-uses? 'amount-original-currency columns-used)
             (_ "Original"))
     (add-if (column-uses? 'running-balance columns-used)
             (_ "Balance"))))

  (let* ((work-to-do (length splits))
         (work-done 0)
         (table (gnc:make-html-table))
         (used-columns (build-columns-used))
         (headings (make-heading-list used-columns))
         (amount-headings (make-amount-heading-list used-columns))
         (width (length headings))
         (width-amount (length amount-headings))
         (account-types-to-reverse
          (case (opt-val gnc:pagename-display (N_ "Sign Reverses"))
            ((none) '())
            ((income-expense) (list ACCT-TYPE-INCOME ACCT-TYPE-EXPENSE))
            ((credit-accounts)  (list ACCT-TYPE-LIABILITY ACCT-TYPE-PAYABLE
                                      ACCT-TYPE-EQUITY ACCT-TYPE-CREDIT
                                      ACCT-TYPE-INCOME))))
         (is-multiline? (eq? (opt-val gnc:pagename-display optname-detail-level) 'multi-line))
         (export? (opt-val gnc:pagename-general optname-table-export)))

    (define (add-subheading data subheading-style)
      (let ((heading-cell (gnc:make-html-table-cell data)))
        (gnc:html-table-cell-set-colspan! heading-cell (+ width width-amount))
        (gnc:html-table-append-row/markup!
         table subheading-style
         (list heading-cell))))


    (define (add-subtotal-row subtotal-string subtotal-collectors-and-calculated-cells subtotal-style)
      (let* ((row-contents '())
             (subtotal-collectors (map car subtotal-collectors-and-calculated-cells))
             (calculated-cells  (map cadr subtotal-collectors-and-calculated-cells))
             (merge-list (map (lambda (cell) (vector-ref cell 4)) calculated-cells))
             (columns (map (lambda (coll) (coll 'format gnc:make-gnc-monetary #f)) subtotal-collectors))
             (list-of-commodities (delete-duplicates (map gnc:gnc-monetary-commodity (concatenate columns))
                                                     gnc-commodity-equal)))

        (define (retrieve-commodity list-of-monetary commodity)
          (and (not (null? list-of-monetary))
               (if (gnc-commodity-equal (gnc:gnc-monetary-commodity (car list-of-monetary)) commodity)
                   (car list-of-monetary)
                   (retrieve-commodity (cdr list-of-monetary) commodity))))

        (define (add-first-column string)
          (if export?
              (begin
                (addto! row-contents (gnc:make-html-table-cell/markup "total-label-cell" string))
                (for-each (lambda (cell) (addto! row-contents cell))
                          (gnc:html-make-empty-cells (- width 1))))
              (addto! row-contents (gnc:make-html-table-cell/size/markup 1 width "total-label-cell" string))))

        (define (add-columns commodity)
          (let ((merging? #f)
                (merging-subtotal (gnc:make-gnc-numeric 0 1))
                (width 0))
            (for-each (lambda (column merge-entry)
                        (let* ((mon (retrieve-commodity column commodity))
                               (col (and mon (gnc:gnc-monetary-amount mon)))
                               (merge? (vector-ref merge-entry 0))
                               (merge-fn (vector-ref merge-entry 1)))
                          (if merge?
                              ;; We're merging. Run merge-fn (usu gnc-numeric-add or sub)
                              ;; and store total in dual-subtotal. Do NOT add column.
                              (begin
                                (if column-amount
                                    (set! merging-subtotal
                                          (merge-fn merging-subtotal column-amount)))
                                (set! merging? #t)
                                (if col
                                    (set! merging-subtotal
                                          (merge-fn merging-subtotal col GNC-DENOM-AUTO GNC-RND-ROUND)))
                                (set! width (+ width 1)))
                              (if merging?
                                  (begin
                                    ;; We've completed merging. Add this column amount
                                    ;; and add the columns.
                                    (set! merging? #f)
                                    (if col
                                        (set! merging-subtotal
                                              (merge-fn merging-subtotal column-amount)))
                                    (set! width (+ width 1))
                                    (addto! row-contents
                                            (gnc:make-html-table-cell/size/markup
                                             1 width "total-number-cell"
                                             (gnc:make-gnc-monetary commodity merging-subtotal)))
                                    (set! width 0)
                                    (set! merging-subtotal (gnc:make-gnc-numeric 0 1)))
                                  ;; Default; not merging/completed merge. Just
                                  ;; display monetary amount
                                  (addto! row-contents
                                          (gnc:make-html-table-cell/markup "total-number-cell" mon))))))
                      columns
                      merge-list)))

        ;;first row
        (add-first-column subtotal-string)
        (add-columns (and (pair? list-of-commodities)
                          (car list-of-commodities))) ;to account for empty-row subtotals
        (gnc:html-table-append-row/markup! table subtotal-style (reverse row-contents))

        ;;subsequent rows
        (if (pair? list-of-commodities)
            (for-each (lambda (commodity)
                        (set! row-contents '())
                        (add-first-column "")
                        (add-columns commodity)
                        (gnc:html-table-append-row/markup! table subtotal-style (reverse row-contents)))
                      (cdr list-of-commodities)))))

    (define (total-string str) (string-append (_ "Total For ") str))

    ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;
    ;; calculated-cells
    ;;
    ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (define calculated-cells
      (letrec
          ((damount (lambda (s) (if (gnc:split-voided? s)
                                    (xaccSplitVoidFormerAmount s)
                                    (xaccSplitGetAmount s))))
           (trans-date (lambda (s) (gnc-transaction-get-date-posted (xaccSplitGetTransaction s))))
           (currency (lambda (s) (xaccAccountGetCommodity (xaccSplitGetAccount s))))
           (report-currency (lambda (s) (if (opt-val gnc:pagename-general optname-common-currency)
                                            (opt-val gnc:pagename-general optname-currency)
                                            (currency s))))
           (convert (lambda (s num)
                      (gnc:exchange-by-pricedb-nearest
                       (gnc:make-gnc-monetary (currency s) num)
                       (report-currency s)
                       ;; Use midday as the transaction time so it matches a price
                       ;; on the same day.  Otherwise it uses midnight which will
                       ;; likely match a price on the previous day
                       (timespecCanonicalDayTime trans-date))))
           (split-value (lambda (s) (convert s (damount s)))) ; used for correct debit/credit
           (amount (lambda (s) (split-value s)))
           (debit-amount (lambda (s) (and (gnc-numeric-positive-p (gnc:gnc-monetary-amount (split-value s)))
                                          (split-value s))))
           (credit-amount (lambda (s) (if (gnc-numeric-positive-p (gnc:gnc-monetary-amount (split-value s)))
                                          #f
                                          (gnc:monetary-neg (split-value s)))))
           (original-amount (lambda (s) (gnc:make-gnc-monetary (currency s) (damount s))))
           (running-balance (lambda (s) (gnc:make-gnc-monetary (currency s) (xaccSplitGetBalance s)))))
        (append
         ;; each column will be a vector
         ;; (vector heading calculator-function reverse-column? subtotal? (vector merge? merging-function))
         ;; (calculator-function split) to obtain amount
         ;; reverse? to optionally reverse signs
         ;; subtotal? to allow subtotals (ie irrelevant for running balance)
         ;; merge? to merge with the next cell (ie for debit/credit cells)
         ;; merging-function - function (usually gnc-numeric-add/sub-fixed to apply to merging-subtotal
         (if (column-uses? 'amount-single used-columns)
             (list (vector "Amount" amount #t #t (vector #f #f)))
             '())
         (if (column-uses? 'amount-double used-columns)
             (list (vector "Debit" debit-amount #f #t (vector #t gnc-numeric-add-fixed))
                   (vector "Credit" credit-amount #f #t (vector #f gnc-numeric-sub-fixed)))
             '())
         (if (column-uses? 'amount-original-currency used-columns)
             (list (vector "Original" original-amount #t #t (vector #f #f)))
             '())
         (if (column-uses? 'running-balance used-columns)
             (list (vector "Running Balance" running-balance #t #f (vector #f #f)))
             '()))))

    ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ;; renderers

    ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ;; display an account name depending on the options the user has set
    (define (account-namestring account show-account-code? show-account-name? show-account-full-name?)
      ;;# on multi-line splits we can get an empty ('()) account
      (if (null? account)
          (_ "Split Transaction")
          (string-append
           ;; display account code?
           (if show-account-code?
               (string-append (xaccAccountGetCode account) " ")
               "")
           ;; display account name?
           (if show-account-name?
               ;; display full account name?
               (if show-account-full-name?
                   (gnc-account-get-full-name account)
                   (xaccAccountGetName account))
               ""))))

    (define (render-date renderer-key split)
      ((case renderer-key
         ((week) gnc:date-get-week-year-string)
         ((month) gnc:date-get-month-year-string)
         ((quarter) gnc:date-get-quarter-year-string)
         ((year) gnc:date-get-year-string))
       (gnc:timepair->date
        (gnc-transaction-get-date-posted
         (xaccSplitGetParent split)))))

    (define (render-account renderer-key split anchor?)
      (let* ((account (case renderer-key
                        ((account) (xaccSplitGetAccount split))
                        ((other-acc) (xaccSplitGetAccount (xaccSplitGetOtherSplit split)))))
             (name (account-namestring account
                                       (column-uses? 'sort-account-code      used-columns)
                                       #t
                                       (column-uses? 'sort-account-full-name used-columns)))
             (description (if (and (column-uses? 'sort-account-description used-columns)
                                   (not (string-null? (xaccAccountGetDescription account))))
                              (string-append ": " (xaccAccountGetDescription account))
                              "")))
        (if (and anchor? (not (null? account))) ;html anchor for 2-split transactions only
            (gnc:make-html-text
             (gnc:html-markup-anchor (gnc:account-anchor-text account) name)
             description)
            name)))

    (define (render-summary split renderer-key anchor?)
      (case renderer-key
        ((week month quarter year) (render-date renderer-key split))
        ((account other-acc) (render-account renderer-key split anchor?))
        (else #f)))

    (define (render-grand-total)
      (_ "Grand Total"))

    ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;
    ;; add-split-row
    ;;
    ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (define (add-split-row split cell-calculators row-style transaction-row?)
      (let* ((row-contents '())
             (trans (xaccSplitGetParent split)))

        (define cells
          (map (lambda (cell)
                 (let* ((calculator (vector-ref cell 1))
                        (reverse? (vector-ref cell 2))
                        (subtotal? (vector-ref cell 3))
                        (calculated (calculator split)))
                   (vector calculated reverse? subtotal?)))
               cell-calculators))

        (if (column-uses? 'date used-columns)
            (addto! row-contents
                    (if transaction-row?
                        (gnc:make-html-table-cell/markup
                         "date-cell"
                         (gnc-print-date (gnc-transaction-get-date-posted trans)))
                        "")))

        (if (column-uses? 'reconciled-date used-columns)
            (addto! row-contents
                    (gnc:make-html-table-cell/markup
                     "date-cell"
                     (let ((date (gnc-split-get-date-reconciled split)))
                       (if (equal? date (cons 0 0))
                           ""
                           (gnc-print-date date))))))

        (if (column-uses? 'num used-columns)
            (addto! row-contents
                    (if transaction-row?
                        (if BOOK-SPLIT-ACTION
                            (let* ((num (gnc-get-num-action trans split))
                                   (t-num (if (if (gnc:lookup-option options
                                                                     gnc:pagename-display
                                                                     (N_ "Trans Number"))
                                                  (opt-val gnc:pagename-display (N_ "Trans Number"))
                                                  "")
                                              (gnc-get-num-action trans #f)
                                              ""))
                                   (num-string (if (string-null? t-num)
                                                   num
                                                   (string-append num "/" t-num))))
                              (gnc:make-html-table-cell/markup "text-cell" num-string))
                            (gnc:make-html-table-cell/markup "text-cell"
                                                             (gnc-get-num-action trans split)))
                        "")))

        (if (column-uses? 'description used-columns)
            (addto! row-contents
                    (if transaction-row?
                        (gnc:make-html-table-cell/markup
                         "text-cell"
                         (xaccTransGetDescription trans))
                        "")))

        (if (column-uses? 'memo used-columns)
            (let ((memo (xaccSplitGetMemo split)))
              (if (and (string-null? memo) (column-uses? 'notes used-columns))
                  (addto! row-contents (xaccTransGetNotes trans))
                  (addto! row-contents memo))))

        (if (or (column-uses? 'account-name used-columns) (column-uses? 'account-code used-columns))
            (addto! row-contents (account-namestring (xaccSplitGetAccount split)
                                                     (column-uses? 'account-code      used-columns)
                                                     (column-uses? 'account-name      used-columns)
                                                     (column-uses? 'account-full-name used-columns))))

        (if (or (column-uses? 'other-account-name used-columns) (column-uses? 'other-account-code used-columns))
            (addto! row-contents (account-namestring (xaccSplitGetAccount (xaccSplitGetOtherSplit split))
                                                     (column-uses? 'other-account-code      used-columns)
                                                     (column-uses? 'other-account-name      used-columns)
                                                     (column-uses? 'other-account-full-name used-columns))))

        (if (column-uses? 'shares used-columns)
            (addto! row-contents (xaccSplitGetAmount split)))

        (if (column-uses? 'price used-columns)
            (addto! row-contents  (gnc:make-gnc-monetary (xaccTransGetCurrency parent)
                                                         (xaccSplitGetSharePrice split))))

        (for-each (lambda (cell)
                    (let ((cell-content (vector-ref cell 0))
                          (reverse? (vector-ref cell 1))
                          (reverse-amount (lambda (mon)
                                            (let ((currency (gnc:gnc-monetary-commodity mon))
                                                  (amount (gnc:gnc-monetary-amount mon)))
                                              (gnc:make-gnc-monetary
                                               currency
                                               (gnc-numeric-neg amount))))))
                      (if cell-content
                          (addto! row-contents
                                  (gnc:make-html-table-cell/markup
                                   "number-cell"
                                   (gnc:html-transaction-anchor
                                    trans
                                    (if (and reverse?
                                             (member (xaccAccountGetType account) account-types-to-reverse))
                                        (reverse-amount cell-content)
                                        cell-content))))
                          (addto! row-contents (gnc:html-make-empty-cell)))))
                  cells)

        (gnc:html-table-append-row/markup! table row-style (reverse row-contents))

        (map (lambda (cell)
               (let ((cell-content (vector-ref cell 0))
                     (subtotal? (vector-ref cell 2)))
                 (and subtotal? cell-content)))
             cells)))

    ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ;; do-rows-with-subtotals

    ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (define (do-rows-with-subtotals splits
                                    odd-row?
                                    primary-subtotal-collectors
                                    secondary-subtotal-collectors
                                    total-collectors)

      (gnc:report-percent-done (* 100 (/ work-done work-to-do)))

      (set! work-done (+ 1 work-done))

      (if (null? splits)
          
          (begin
            
            (gnc:html-table-append-row/markup!
             table def:grand-total-style
             (list
              (gnc:make-html-table-cell/size
               1 (+ width width-amount) (gnc:make-html-text (gnc:html-markup-hr)))))

            (if (opt-val gnc:pagename-display "Totals")
                (add-subtotal-row (render-grand-total) (zip total-collectors calculated-cells) def:grand-total-style)))

          (let* ((current (car splits))
                 (rest (cdr splits))
                 (next (if (null? rest) #f (car rest)))
                 (split-values (add-split-row
                                current
                                calculated-cells
                                (if is-multiline? def:normal-row-style
                                    (if odd-row?
                                        def:normal-row-style
                                        def:alternate-row-style))
                                #t)))

            (if is-multiline?
                (for-each
                 (lambda (othersplits)
                   (add-split-row othersplits calculated-cells def:alternate-row-style #f))
                 (delete current (xaccTransGetSplitList (xaccSplitGetParent current)))))

            (map (lambda (collector value)
                   (if value
                       (collector 'add (gnc:gnc-monetary-commodity value) (gnc:gnc-monetary-amount value))))
                 primary-subtotal-collectors
                 split-values)

            (map (lambda (collector value)
                   (if value
                       (collector 'add (gnc:gnc-monetary-commodity value) (gnc:gnc-monetary-amount value))))
                 secondary-subtotal-collectors
                 split-values)

            (map (lambda (collector value)
                   (if value
                       (collector 'add (gnc:gnc-monetary-commodity value) (gnc:gnc-monetary-amount value))))
                 total-collectors
                 split-values)

            (if (and primary-subtotal-comparator
                     (or (not next)
                         (and next
                              (not (equal? (primary-subtotal-comparator current)
                                           (primary-subtotal-comparator next))))))

                (begin
                  (if secondary-subtotal-comparator
                      (begin
                        (add-subtotal-row (total-string
                                           (render-summary current secondary-renderer-key #f))
                                          (zip secondary-subtotal-collectors calculated-cells)
                                          def:secondary-subtotal-style)
                        (for-each (lambda (coll) (coll 'reset #f #f))
                                  secondary-subtotal-collectors)))
                  (add-subtotal-row (total-string
                                     (render-summary current primary-renderer-key #f))
                                    (zip primary-subtotal-collectors calculated-cells)
                                    def:primary-subtotal-style)
                  (for-each (lambda (coll) (coll 'reset #f #f))
                            primary-subtotal-collectors)
                  (if next
                      (begin
                        (add-subheading (render-summary next primary-renderer-key #t)
                                        def:primary-subtotal-style)
                        (if secondary-subtotal-comparator
                            (add-subheading (render-summary next secondary-renderer-key #t)
                                            def:secondary-subtotal-style)))))

                (if (and secondary-subtotal-comparator
                         (or (not next)
                             (and next
                                  (not (equal? (secondary-subtotal-comparator current)
                                               (secondary-subtotal-comparator next))))))
                    (begin (add-subtotal-row (total-string
                                              (render-summary current secondary-renderer-key #f))
                                             (zip secondary-subtotal-collectors calculated-cells)
                                             def:secondary-subtotal-style)
                           (for-each (lambda (coll) (coll 'reset #f #f))
                                     secondary-subtotal-collectors)
                           (if next
                               (add-subheading (render-summary next secondary-renderer-key #t)
                                               def:secondary-subtotal-style)))))

            (do-rows-with-subtotals rest
                                    (not odd-row?)
                                    primary-subtotal-collectors
                                    secondary-subtotal-collectors
                                    total-collectors))))

    (gnc:html-table-set-col-headers! table (concatenate (list headings amount-headings)))

    (if primary-renderer-key
        (add-subheading (render-summary (car splits) primary-renderer-key #t)
                        def:primary-subtotal-style))

    (if secondary-renderer-key
        (add-subheading (render-summary (car splits) secondary-renderer-key #t)
                        def:secondary-subtotal-style))

    (do-rows-with-subtotals splits #t
                            (map (lambda (x) (gnc:make-commodity-collector)) calculated-cells)
                            (map (lambda (x) (gnc:make-commodity-collector)) calculated-cells)
                            (map (lambda (x) (gnc:make-commodity-collector)) calculated-cells))

    table))

;; ;;;;;;;;;;;;;;;;;;;;
;; Here comes the renderer function for this report.


(define (trep-renderer report-obj)
  (define options (gnc:report-options report-obj))
  (define (opt-val section name) (gnc:option-value (gnc:lookup-option options section name)))
  (define BOOK-SPLIT-ACTION (qof-book-use-split-action-for-num-field (gnc-get-current-book)))

  (define (subtotal-get-info name-sortkey name-subtotal name-date-subtotal info)
    ;; The value of the sorting-key multichoice option.
    (let ((sortkey (opt-val pagename-sorting name-sortkey)))
      (if (member sortkey DATE-SORTING-TYPES)
          ;; If sorting by date, look up the value of the
          ;; date-subtotalling multichoice option and return the
          ;; corresponding funcs in the assoc-list.
          (date-subtotal-get-info (opt-val pagename-sorting name-date-subtotal) info)
          ;; For everything else: 1. check whether sortkey has
          ;; subtotalling enabled at all, 2. check whether the
          ;; enable-subtotal boolean option is #t, 3. look up the
          ;; appropriate funcs in the assoc-list.
          (and (member sortkey SUBTOTAL-ENABLED)
               (and (opt-val pagename-sorting name-subtotal)
                    (sortkey-get-info sortkey info))))))

  (define (is-filter-member split account-list)
    (let* ((txn (xaccSplitGetParent split))
           (splitcount (xaccTransCountSplits txn))
           (other-account (xaccSplitGetAccount (xaccSplitGetOtherSplit split)))
           (splits-equal? (lambda (s1 s2) (xaccSplitEqual s1 s2 #t #f #f)))
           (other-splits (delete split (xaccTransGetSplitList txn) splits-equal?))
           (other-accounts (map xaccSplitGetAccount other-splits))
           (is-in-account-list? (lambda (acc) (member acc account-list))))
      (cond
        ;; A 2-split transaction - test separately so it can be optimized
        ;; to significantly reduce the number of splits to traverse
        ;; in guile code
        ((= splitcount 2) (is-in-account-list? other-account))
        ;; A multi-split transaction - run over all splits
        ((> splitcount 2) (or-map is-in-account-list? other-accounts))
        ;; Single transaction splits
        (else #f))))

  (gnc:report-starting reportname)

  (let* ((document (gnc:make-html-document))
         (account-matcher (opt-val pagename-filter optname-account-matcher))
         (account-matcher-regexp (and (opt-val pagename-filter optname-account-matcher-regex)
                                      (make-regexp account-matcher)))
         (c_account_0 (opt-val gnc:pagename-accounts optname-accounts))
         (c_account_1 (filter
                       (lambda (acc)
                         (if account-matcher-regexp
                             (regexp-exec account-matcher-regexp (gnc-account-get-full-name acc))
                             (string-contains (gnc-account-get-full-name acc) account-matcher)))
                       c_account_0))
         (c_account_2 (opt-val gnc:pagename-accounts optname-filterby))
         (filter-mode (opt-val gnc:pagename-accounts optname-filtertype))
         (begindate (gnc:timepair-start-day-time
                     (gnc:date-option-absolute-time
                      (opt-val gnc:pagename-general optname-startdate))))
         (enddate (gnc:timepair-end-day-time
                   (gnc:date-option-absolute-time
                    (opt-val gnc:pagename-general optname-enddate))))
         (transaction-matcher (opt-val pagename-filter optname-transaction-matcher))
         (transaction-matcher-regexp (and (opt-val pagename-filter optname-transaction-matcher-regex)
                                          (make-regexp transaction-matcher)))
         (reconcile-status-filter (opt-val pagename-filter optname-reconcile-status))
         (report-title (opt-val gnc:pagename-general gnc:optname-reportname))
         (primary-key (opt-val pagename-sorting optname-prime-sortkey))
         (primary-order (opt-val pagename-sorting optname-prime-sortorder))
         (primary-date-subtotal (opt-val pagename-sorting optname-prime-date-subtotal))
         (secondary-key (opt-val pagename-sorting optname-sec-sortkey))
         (secondary-order (opt-val pagename-sorting optname-sec-sortorder))
         (secondary-date-subtotal (opt-val pagename-sorting optname-sec-date-subtotal))
         (void-status (opt-val gnc:pagename-accounts optname-void-transactions))
         (splits '())
         (custom-sort? (or (and (member primary-key DATE-SORTING-TYPES)   ; this will remain
                                (not (eq? primary-date-subtotal 'none)))  ; until qof-query
                           (and (member secondary-key DATE-SORTING-TYPES) ; is upgraded
                                (not (eq? secondary-date-subtotal 'none)))))
         (query (qof-query-create-for-splits)))

    (define (generic-less? X Y key date-subtotal ascend?)
      (define comparator-function
        (if (member key DATE-SORTING-TYPES)
            (let* ((date (lambda (s)
                           (case key
                             ((date) (xaccTransGetDate (xaccSplitGetParent s)))
                             ((reconciled-date) (xaccSplitGetDateReconciled s)))))
                   (year    (lambda (s) (gnc:date-get-year (gnc-localtime (date s)))))
                   (month   (lambda (s) (gnc:date-get-month (gnc-localtime (date s)))))
                   (quarter (lambda (s) (gnc:date-get-quarter (gnc-localtime (date s)))))
                   (week    (lambda (s) (gnc:date-get-week (gnc-localtime (date s)))))
                   (secs    (lambda (s) (date s))))
              (case date-subtotal
                ((yearly)    (lambda (s) (year s)))
                ((monthly)   (lambda (s) (+ (* 100 (year s)) (month s))))
                ((quarterly) (lambda (s) (+ (*  10 (year s)) (quarter s))))
                ((weekly)    (lambda (s) (week s)))
                ((none)      (lambda (s) (secs s)))))
            (case key
              ((account-name) (lambda (s) (gnc-account-get-full-name (xaccSplitGetAccount s))))
              ((account-code) (lambda (s) (xaccAccountGetCode (xaccSplitGetAccount s))))
              ((corresponding-acc-name) (lambda (s) (xaccSplitGetCorrAccountFullName s)))
              ((corresponding-acc-code) (lambda (s) (xaccSplitGetCorrAccountCode s)))
              ((amount) (lambda (s) (gnc-numeric-to-double (xaccSplitGetValue s))))
              ((description) (lambda (s) (xaccTransGetDescription (xaccSplitGetParent s))))
              ((number) (lambda (s)
                          (if BOOK-SPLIT-ACTION
                              (xaccSplitGetAction s)
                              (xaccTransGetNum (xaccSplitGetParent s)))))
              ((t-number) (lambda (s) (xaccTransGetNum (xaccSplitGetParent s))))
              ((register-order) (lambda (s) #f))
              ((memo) (lambda (s) (xaccSplitGetMemo s)))
              ((none) (lambda (s) #f)))))
      (cond
       ((string? (comparator-function X)) ((if ascend? string<? string>?) (comparator-function X) (comparator-function Y)))
       ((comparator-function X)           ((if ascend? < >)               (comparator-function X) (comparator-function Y)))
       (else                              #f)))

    (define (primary-comparator? X Y)
      (generic-less? X Y primary-key
                     primary-date-subtotal
                     (eq? primary-order 'ascend)))

    (define (secondary-comparator? X Y)
      (generic-less? X Y secondary-key
                     secondary-date-subtotal
                     (eq? secondary-order 'ascend)))

    ;; This will, by default, sort the split list by ascending posted-date.
    (define (date-comparator? X Y)
      (generic-less? X Y 'date 'none #t))



    (if (or (null? c_account_1) (and-map not c_account_1))

        (if (null? c_account_0)

            ;; error condition: no accounts specified
            (gnc:html-document-add-object!
             document
             (gnc:html-make-no-account-warning report-title (gnc:report-id report-obj)))

            ;; error condition: accounts were specified but none matched string/regex
            (gnc:html-document-add-object!
             document
             (gnc:make-html-text
              (gnc:html-markup-h2 NO-MATCHING-ACCT-HEADER)
              (gnc:html-markup-p NO-MATCHING-ACCT-TEXT))))

        (begin

          (qof-query-set-book query (gnc-get-current-book))
          (xaccQueryAddAccountMatch query c_account_1 QOF-GUID-MATCH-ANY QOF-QUERY-AND)
          (xaccQueryAddDateMatchTS query #t begindate #t enddate QOF-QUERY-AND)
          (case void-status
            ((non-void-only) (gnc:query-set-match-non-voids-only! query (gnc-get-current-book)))
            ((void-only)     (gnc:query-set-match-voids-only! query (gnc-get-current-book)))
            (else #f))
          (if (not custom-sort?)
              (begin
                (qof-query-set-sort-order query
                                          (sortkey-get-info primary-key 'sortkey)
                                          (sortkey-get-info secondary-key 'sortkey)
                                          '())
                (qof-query-set-sort-increasing query
                                               (eq? primary-order 'ascend)
                                               (eq? secondary-order 'ascend)
                                               #t)))
          (set! splits (qof-query-run query))

          (qof-query-destroy query)

          (if custom-sort?
              (begin
                (set! splits (stable-sort! splits date-comparator?))
                (set! splits (stable-sort! splits secondary-comparator?))
                (set! splits (stable-sort! splits primary-comparator?))))

          ;; Combined Filter:
          ;; - include/exclude splits to/from selected accounts
          ;; - substring/regex matcher for Transaction Description/Notes/Memo
          ;; - by reconcile status
          (set! splits (filter
                        (lambda (split)
                          (let* ((trans (xaccSplitGetParent split))
                                 (match? (lambda (str)
                                           (if transaction-matcher-regexp
                                               (regexp-exec transaction-matcher-regexp str)
                                               (string-contains str transaction-matcher)))))
                            (and (case filter-mode
                                   ((none) #t)
                                   ((include) (is-filter-member split c_account_2))
                                   ((exclude) (not (is-filter-member split c_account_2))))
                                 (or (string-null? transaction-matcher) ; null-string = ignore filters
                                     (match? (xaccTransGetDescription trans))
                                     (match? (xaccTransGetNotes trans))
                                     (match? (xaccSplitGetMemo split)))
                                 (or (not reconcile-status-filter) ; #f = ignore next filter
                                     (member (xaccSplitGetReconcile split) reconcile-status-filter)))))
                        splits))

          (if (null? splits)

              ;; error condition: no splits found
              (gnc:html-document-add-object!
               document
               (gnc:make-html-text
                (gnc:html-markup-h2 NO-MATCHING-TRANS-HEADER)
                (gnc:html-markup-p NO-MATCHING-TRANS-TEXT)))

              (let ((table (make-split-table
                            splits options
                            (subtotal-get-info optname-prime-sortkey
                                               optname-prime-subtotal
                                               optname-prime-date-subtotal
                                               'split-sortvalue)
                            (subtotal-get-info optname-sec-sortkey
                                               optname-sec-subtotal
                                               optname-sec-date-subtotal
                                               'split-sortvalue)
                            (subtotal-get-info optname-prime-sortkey
                                               optname-prime-subtotal
                                               optname-prime-date-subtotal
                                               'renderer-key)
                            (subtotal-get-info optname-sec-sortkey
                                               optname-sec-subtotal
                                               optname-sec-date-subtotal
                                               'renderer-key))))

                (gnc:html-document-set-title! document report-title)

                (gnc:html-document-add-object!
                 document
                 (gnc:make-html-text
                  (gnc:html-markup-h3
                   (sprintf #f
                            (_ "From %s to %s")
                            (gnc-print-date begindate)
                            (gnc-print-date enddate)))))

                (gnc:html-document-add-object! document table)))))

    (gnc:report-finished)

    document))

;; Define the report.
(gnc:define-report

 'version 1

 'name reportname
 'report-guid "2fe3b9833af044abb929a88d5a59620f"

 'options-generator trep-options-generator
 'renderer trep-renderer)
