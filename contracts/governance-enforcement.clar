;; Governance Enforcement Contract
;; Enforces data governance policies and rules

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u180))
(define-constant ERR-POLICY-NOT-FOUND (err u181))
(define-constant ERR-VIOLATION-NOT-FOUND (err u182))
(define-constant ERR-INVALID-SEVERITY (err u183))
(define-constant ERR-POLICY-ALREADY-EXISTS (err u184))
(define-constant ERR-INVALID-ACTION (err u185))

;; Data Variables
(define-data-var next-policy-id uint u1)
(define-data-var next-violation-id uint u1)
(define-data-var next-audit-id uint u1)
(define-data-var enforcement-enabled bool true)

;; Data Maps
(define-map governance-policies
  uint
  {
    name: (string-ascii 256),
    description: (string-utf8 1024),
    policy-type: (string-ascii 50),
    rules: (string-utf8 2048),
    severity: (string-ascii 20),
    enforcement-action: (string-ascii 100),
    created-by: principal,
    created-at: uint,
    active: bool,
    violation-count: uint
  }
)

(define-map policy-by-name
  (string-ascii 256)
  uint
)

(define-map policy-violations
  uint
  {
    policy-id: uint,
    violator: principal,
    violation-type: (string-ascii 50),
    description: (string-utf8 512),
    data-reference: (string-ascii 256),
    detected-at: uint,
    severity: (string-ascii 20),
    status: (string-ascii 20),
    remediation-required: bool,
    remediation-deadline: uint
  }
)

(define-map compliance-audits
  uint
  {
    audit-name: (string-ascii 256),
    auditor: principal,
    audit-scope: (string-utf8 512),
    start-date: uint,
    end-date: uint,
    policies-checked: (list 20 uint),
    violations-found: uint,
    compliance-score: uint,
    status: (string-ascii 20),
    report-hash: (string-ascii 256)
  }
)

(define-map remediation-actions
  uint
  {
    violation-id: uint,
    action-type: (string-ascii 50),
    description: (string-utf8 512),
    assigned-to: principal,
    due-date: uint,
    status: (string-ascii 20),
    completed-at: uint,
    effectiveness-score: uint
  }
)

(define-map enforcement-metrics
  (string-ascii 50)
  {
    metric-name: (string-ascii 50),
    total-violations: uint,
    resolved-violations: uint,
    average-resolution-time: uint,
    compliance-rate: uint,
    last-updated: uint
  }
)

(define-map user-compliance-scores
  principal
  {
    user-address: principal,
    compliance-score: uint,
    violations-count: uint,
    resolved-count: uint,
    last-violation: uint,
    reputation-impact: uint
  }
)

;; Private Functions
(define-private (is-valid-severity (severity (string-ascii 20)))
  (or
    (is-eq severity "critical")
    (is-eq severity "high")
    (is-eq severity "medium")
    (is-eq severity "low")
  )
)

(define-private (is-valid-policy-type (policy-type (string-ascii 50)))
  (or
    (is-eq policy-type "data-access")
    (is-eq policy-type "data-quality")
    (is-eq policy-type "data-retention")
    (is-eq policy-type "data-privacy")
    (is-eq policy-type "data-sharing")
  )
)

(define-private (is-valid-violation-status (status (string-ascii 20)))
  (or
    (is-eq status "open")
    (is-eq status "investigating")
    (is-eq status "resolved")
    (is-eq status "dismissed")
  )
)

(define-private (calculate-compliance-score (total-violations uint) (resolved-violations uint))
  (if (is-eq total-violations u0)
    u100
    (/ (* resolved-violations u100) total-violations)
  )
)

;; Public Functions
(define-public (create-governance-policy
  (name (string-ascii 256))
  (description (string-utf8 1024))
  (policy-type (string-ascii 50))
  (rules (string-utf8 2048))
  (severity (string-ascii 20))
  (enforcement-action (string-ascii 100))
)
  (let (
    (policy-id (var-get next-policy-id))
  )
    (asserts! (is-none (map-get? policy-by-name name)) ERR-POLICY-ALREADY-EXISTS)
    (asserts! (is-valid-policy-type policy-type) ERR-INVALID-ACTION)
    (asserts! (is-valid-severity severity) ERR-INVALID-SEVERITY)

    (map-set governance-policies policy-id {
      name: name,
      description: description,
      policy-type: policy-type,
      rules: rules,
      severity: severity,
      enforcement-action: enforcement-action,
      created-by: tx-sender,
      created-at: block-height,
      active: true,
      violation-count: u0
    })

    (map-set policy-by-name name policy-id)
    (var-set next-policy-id (+ policy-id u1))

    (ok policy-id)
  )
)

(define-public (report-policy-violation
  (policy-id uint)
  (violator principal)
  (violation-type (string-ascii 50))
  (description (string-utf8 512))
  (data-reference (string-ascii 256))
)
  (let (
    (violation-id (var-get next-violation-id))
    (policy-data (unwrap! (map-get? governance-policies policy-id) ERR-POLICY-NOT-FOUND))
    (deadline (+ block-height u1440)) ;; 10 days in blocks
  )
    (asserts! (get active policy-data) ERR-POLICY-NOT-FOUND)

    (map-set policy-violations violation-id {
      policy-id: policy-id,
      violator: violator,
      violation-type: violation-type,
      description: description,
      data-reference: data-reference,
      detected-at: block-height,
      severity: (get severity policy-data),
      status: "open",
      remediation-required: true,
      remediation-deadline: deadline
    })

    ;; Update policy violation count
    (map-set governance-policies policy-id
      (merge policy-data {
        violation-count: (+ (get violation-count policy-data) u1)
      })
    )

    ;; Update user compliance score
    (update-user-compliance-score violator)

    (var-set next-violation-id (+ violation-id u1))
    (ok violation-id)
  )
)

(define-public (resolve-violation (violation-id uint) (resolution-notes (string-utf8 512)))
  (let (
    (violation-data (unwrap! (map-get? policy-violations violation-id) ERR-VIOLATION-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status violation-data) "open") ERR-INVALID-ACTION)

    (map-set policy-violations violation-id
      (merge violation-data { status: "resolved" })
    )

    ;; Update user compliance score
    (update-user-compliance-score (get violator violation-data))

    (ok true)
  )
)

(define-public (conduct-compliance-audit
  (audit-name (string-ascii 256))
  (audit-scope (string-utf8 512))
  (policies-to-check (list 20 uint))
)
  (let (
    (audit-id (var-get next-audit-id))
  )
    (map-set compliance-audits audit-id {
      audit-name: audit-name,
      auditor: tx-sender,
      audit-scope: audit-scope,
      start-date: block-height,
      end-date: u0,
      policies-checked: policies-to-check,
      violations-found: u0,
      compliance-score: u0,
      status: "in-progress",
      report-hash: ""
    })

    (var-set next-audit-id (+ audit-id u1))
    (ok audit-id)
  )
)

(define-public (complete-compliance-audit
  (audit-id uint)
  (violations-found uint)
  (compliance-score uint)
  (report-hash (string-ascii 256))
)
  (let (
    (audit-data (unwrap! (map-get? compliance-audits audit-id) ERR-VIOLATION-NOT-FOUND))
  )
    (asserts! (is-eq (get auditor audit-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status audit-data) "in-progress") ERR-INVALID-ACTION)
    (asserts! (<= compliance-score u100) ERR-INVALID-SEVERITY)

    (map-set compliance-audits audit-id
      (merge audit-data {
        end-date: block-height,
        violations-found: violations-found,
        compliance-score: compliance-score,
        status: "completed",
        report-hash: report-hash
      })
    )

    (ok true)
  )
)

(define-public (assign-remediation-action
  (violation-id uint)
  (action-type (string-ascii 50))
  (description (string-utf8 512))
  (assigned-to principal)
  (due-date uint)
)
  (let (
    (violation-data (unwrap! (map-get? policy-violations violation-id) ERR-VIOLATION-NOT-FOUND))
    (action-id (var-get next-audit-id))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (get remediation-required violation-data) ERR-INVALID-ACTION)

    (map-set remediation-actions action-id {
      violation-id: violation-id,
      action-type: action-type,
      description: description,
      assigned-to: assigned-to,
      due-date: due-date,
      status: "assigned",
      completed-at: u0,
      effectiveness-score: u0
    })

    (var-set next-audit-id (+ action-id u1))
    (ok action-id)
  )
)

(define-private (update-user-compliance-score (user principal))
  (let (
    (current-score (default-to
      {
        user-address: user,
        compliance-score: u100,
        violations-count: u0,
        resolved-count: u0,
        last-violation: u0,
        reputation-impact: u0
      }
      (map-get? user-compliance-scores user)
    ))
    (new-violations (+ (get violations-count current-score) u1))
    (new-compliance-score (calculate-compliance-score new-violations (get resolved-count current-score)))
  )
    (map-set user-compliance-scores user {
      user-address: user,
      compliance-score: new-compliance-score,
      violations-count: new-violations,
      resolved-count: (get resolved-count current-score),
      last-violation: block-height,
      reputation-impact: (if (< new-compliance-score u70) u20 u0)
    })
    true
  )
)

(define-public (toggle-enforcement (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set enforcement-enabled enabled)
    (ok enabled)
  )
)

;; Read-only Functions
(define-read-only (get-governance-policy (policy-id uint))
  (map-get? governance-policies policy-id)
)

(define-read-only (get-policy-by-name (name (string-ascii 256)))
  (match (map-get? policy-by-name name)
    policy-id (map-get? governance-policies policy-id)
    none
  )
)

(define-read-only (get-policy-violation (violation-id uint))
  (map-get? policy-violations violation-id)
)

(define-read-only (get-compliance-audit (audit-id uint))
  (map-get? compliance-audits audit-id)
)

(define-read-only (get-remediation-action (action-id uint))
  (map-get? remediation-actions action-id)
)

(define-read-only (get-user-compliance-score (user principal))
  (map-get? user-compliance-scores user)
)

(define-read-only (get-enforcement-metrics (metric-name (string-ascii 50)))
  (map-get? enforcement-metrics metric-name)
)

(define-read-only (is-enforcement-enabled)
  (var-get enforcement-enabled)
)

(define-read-only (get-next-policy-id)
  (var-get next-policy-id)
)

(define-read-only (get-next-violation-id)
  (var-get next-violation-id)
)

(define-read-only (get-next-audit-id)
  (var-get next-audit-id)
)
