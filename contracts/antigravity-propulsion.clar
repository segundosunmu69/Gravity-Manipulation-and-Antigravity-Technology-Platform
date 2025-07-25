;; Antigravity Propulsion Coordination Contract
;; Manages gravity-defying transportation and flight systems

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-UNIT-ID (err u201))
(define-constant ERR-UNIT-ALREADY-EXISTS (err u202))
(define-constant ERR-INSUFFICIENT-FUEL (err u203))
(define-constant ERR-UNIT-NOT-CERTIFIED (err u204))
(define-constant ERR-INVALID-FLIGHT-PATH (err u205))
(define-constant ERR-AIRSPACE-RESTRICTED (err u206))
(define-constant ERR-UNIT-IN-FLIGHT (err u207))
(define-constant ERR-INVALID-EFFICIENCY (err u208))

;; Maximum operational parameters
(define-constant MAX-ALTITUDE u50000)
(define-constant MAX-VELOCITY u10000)
(define-constant MIN-FUEL-LEVEL u50)
(define-constant MAX-FLIGHT-DURATION u86400) ;; 24 hours in seconds

;; Data structures
(define-map propulsion-units
  { unit-id: uint }
  {
    owner: principal,
    model: (string-ascii 50),
    max-altitude: uint,
    max-velocity: uint,
    fuel-capacity: uint,
    current-fuel: uint,
    is-certified: bool,
    certification-expires: uint,
    is-active: bool,
    current-location: { x: int, y: int, z: int },
    status: (string-ascii 20)
  }
)

(define-map flight-plans
  { flight-id: uint }
  {
    unit-id: uint,
    pilot: principal,
    departure: { x: int, y: int, z: int },
    destination: { x: int, y: int, z: int },
    planned-altitude: uint,
    planned-velocity: uint,
    departure-time: uint,
    estimated-duration: uint,
    is-approved: bool,
    is-active: bool
  }
)

(define-map restricted-airspace
  { zone-id: uint }
  {
    center: { x: int, y: int, z: int },
    radius: uint,
    min-altitude: uint,
    max-altitude: uint,
    restriction-type: (string-ascii 30),
    active-until: uint
  }
)

(define-map certified-pilots principal bool)
(define-data-var next-unit-id uint u1)
(define-data-var next-flight-id uint u1)
(define-data-var next-zone-id uint u1)
(define-data-var system-operational bool true)

;; Authorization and certification
(define-public (certify-pilot (pilot principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set certified-pilots pilot true))
  )
)

(define-public (revoke-pilot-certification (pilot principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-delete certified-pilots pilot))
  )
)

(define-private (is-pilot-certified (pilot principal))
  (default-to false (map-get? certified-pilots pilot))
)

;; Propulsion unit management
(define-public (register-propulsion-unit
  (model (string-ascii 50))
  (max-altitude uint)
  (max-velocity uint)
  (fuel-capacity uint)
)
  (let
    (
      (unit-id (var-get next-unit-id))
    )
    (asserts! (is-pilot-certified tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= max-altitude MAX-ALTITUDE) ERR-INVALID-FLIGHT-PATH)
    (asserts! (<= max-velocity MAX-VELOCITY) ERR-INVALID-FLIGHT-PATH)

    (map-set propulsion-units
      { unit-id: unit-id }
      {
        owner: tx-sender,
        model: model,
        max-altitude: max-altitude,
        max-velocity: max-velocity,
        fuel-capacity: fuel-capacity,
        current-fuel: fuel-capacity,
        is-certified: false,
        certification-expires: u0,
        is-active: false,
        current-location: { x: 0, y: 0, z: 0 },
        status: "registered"
      }
    )

    (var-set next-unit-id (+ unit-id u1))
    (ok unit-id)
  )
)

(define-public (certify-propulsion-unit (unit-id uint) (expiration-block uint))
  (let
    (
      (unit-data (unwrap! (map-get? propulsion-units { unit-id: unit-id }) ERR-INVALID-UNIT-ID))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> expiration-block block-height) ERR-INVALID-FLIGHT-PATH)

    (map-set propulsion-units
      { unit-id: unit-id }
      (merge unit-data {
        is-certified: true,
        certification-expires: expiration-block,
        status: "certified"
      })
    )

    (ok true)
  )
)

(define-public (refuel-unit (unit-id uint) (fuel-amount uint))
  (let
    (
      (unit-data (unwrap! (map-get? propulsion-units { unit-id: unit-id }) ERR-INVALID-UNIT-ID))
      (new-fuel-level (+ (get current-fuel unit-data) fuel-amount))
    )
    (asserts! (is-eq (get owner unit-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fuel-level (get fuel-capacity unit-data)) ERR-INSUFFICIENT-FUEL)

    (map-set propulsion-units
      { unit-id: unit-id }
      (merge unit-data { current-fuel: new-fuel-level })
    )

    (ok true)
  )
)

;; Flight planning and management
(define-public (submit-flight-plan
  (unit-id uint)
  (departure-x int) (departure-y int) (departure-z int)
  (destination-x int) (destination-y int) (destination-z int)
  (planned-altitude uint)
  (planned-velocity uint)
  (departure-time uint)
  (estimated-duration uint)
)
  (let
    (
      (flight-id (var-get next-flight-id))
      (unit-data (unwrap! (map-get? propulsion-units { unit-id: unit-id }) ERR-INVALID-UNIT-ID))
    )
    (asserts! (is-eq (get owner unit-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-certified unit-data) ERR-UNIT-NOT-CERTIFIED)
    (asserts! (> (get certification-expires unit-data) block-height) ERR-UNIT-NOT-CERTIFIED)
    (asserts! (<= planned-altitude (get max-altitude unit-data)) ERR-INVALID-FLIGHT-PATH)
    (asserts! (<= planned-velocity (get max-velocity unit-data)) ERR-INVALID-FLIGHT-PATH)
    (asserts! (>= (get current-fuel unit-data) MIN-FUEL-LEVEL) ERR-INSUFFICIENT-FUEL)
    (asserts! (var-get system-operational) ERR-NOT-AUTHORIZED)

    (map-set flight-plans
      { flight-id: flight-id }
      {
        unit-id: unit-id,
        pilot: tx-sender,
        departure: { x: departure-x, y: departure-y, z: departure-z },
        destination: { x: destination-x, y: destination-y, z: destination-z },
        planned-altitude: planned-altitude,
        planned-velocity: planned-velocity,
        departure-time: departure-time,
        estimated-duration: estimated-duration,
        is-approved: false,
        is-active: false
      }
    )

    (var-set next-flight-id (+ flight-id u1))
    (ok flight-id)
  )
)

(define-public (approve-flight-plan (flight-id uint))
  (let
    (
      (flight-data (unwrap! (map-get? flight-plans { flight-id: flight-id }) ERR-INVALID-FLIGHT-PATH))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (get is-approved flight-data)) ERR-INVALID-FLIGHT-PATH)

    (map-set flight-plans
      { flight-id: flight-id }
      (merge flight-data { is-approved: true })
    )

    (ok true)
  )
)

(define-public (activate-flight (flight-id uint))
  (let
    (
      (flight-data (unwrap! (map-get? flight-plans { flight-id: flight-id }) ERR-INVALID-FLIGHT-PATH))
      (unit-data (unwrap! (map-get? propulsion-units { unit-id: (get unit-id flight-data) }) ERR-INVALID-UNIT-ID))
    )
    (asserts! (is-eq (get pilot flight-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-approved flight-data) ERR-INVALID-FLIGHT-PATH)
    (asserts! (not (get is-active flight-data)) ERR-UNIT-IN-FLIGHT)
    (asserts! (not (get is-active unit-data)) ERR-UNIT-IN-FLIGHT)

    (map-set flight-plans
      { flight-id: flight-id }
      (merge flight-data { is-active: true })
    )

    (map-set propulsion-units
      { unit-id: (get unit-id flight-data) }
      (merge unit-data {
        is-active: true,
        status: "in-flight"
      })
    )

    (ok true)
  )
)

;; Airspace management
(define-public (create-restricted-zone
  (center-x int) (center-y int) (center-z int)
  (radius uint)
  (min-altitude uint) (max-altitude uint)
  (restriction-type (string-ascii 30))
  (active-until uint)
)
  (let
    (
      (zone-id (var-get next-zone-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set restricted-airspace
      { zone-id: zone-id }
      {
        center: { x: center-x, y: center-y, z: center-z },
        radius: radius,
        min-altitude: min-altitude,
        max-altitude: max-altitude,
        restriction-type: restriction-type,
        active-until: active-until
      }
    )

    (var-set next-zone-id (+ zone-id u1))
    (ok zone-id)
  )
)

;; Emergency controls
(define-public (emergency-ground-all-units)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set system-operational false)
    (ok true)
  )
)

(define-public (restore-flight-operations)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set system-operational true)
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-unit-info (unit-id uint))
  (map-get? propulsion-units { unit-id: unit-id })
)

(define-read-only (get-flight-plan (flight-id uint))
  (map-get? flight-plans { flight-id: flight-id })
)

(define-read-only (get-restricted-zone (zone-id uint))
  (map-get? restricted-airspace { zone-id: zone-id })
)

(define-read-only (is-system-operational)
  (var-get system-operational)
)

(define-read-only (get-pilot-certification (pilot principal))
  (default-to false (map-get? certified-pilots pilot))
)
