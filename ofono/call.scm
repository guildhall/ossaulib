
;;;;
;;;; 	Copyright (C) 2012 Neil Jerram.
;;;; 
;;;; This library is free software; you can redistribute it and/or
;;;; modify it under the terms of the GNU General Public License as
;;;; published by the Free Software Foundation; either version 3 of
;;;; the License, or (at your option) any later version.
;;;; 
;;;; This library is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; General Public License for more details.
;;;; 
;;;; You should have received a copy of the GNU General Public License
;;;; along with this library; if not, write to the Free Software
;;;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
;;;; 02110-1301 USA

(define-module (ofono call)
  #:use-module (glib dbus)
  #:use-module (ossau trc)
  #:use-module (ofono modem)
  #:use-module (ofono registration)
  #:export (dial
	    set-incoming-call-proc))

;; This module maps from oFono's D-Bus API for voice call handling to
;; a higher-level and Schemey Scheme API.  As a shorthand we refer to
;; the code using that Scheme API as the UI (for User Interface).

;; (dial number answered failed) - Initiate an outgoing call.
;;
;; NUMBER is the number to dial.
;;
;; ANSWERED is a procedure that (ofono call) will call, if the call is
;; answered, as (ANSWERED make-active-call).  MAKE-ACTIVE-CALL is a
;; procedure that the UI should then call to construct an object that
;; represents the active call, specifying its callbacks for events
;; that may occur on that call: (MAKE-ACTIVE-CALL call-gone
;; dtmf-digit-received).
;;
;;   CALL-GONE should be a thunk that (ofono call) will call if the
;;   active call is terminated by the network or by the other end.
;;
;;   DTMF-DIGIT-RECEIVED should be a procedure that (ofono call) will
;;   call, as (DTMF-DIGIT-RECEIVED digit), if the other end sends a
;;   DTMF digit.
;;
;;   (MAKE-ACTIVE-CALL ...) returns two values: a thunk that the UI
;;   can call when it wants to hang up the call: (hang-up); and a
;;   procedure that the UI can call to send a DTMF digit:
;;   (send-dtmf-digit digit).
;;
;; FAILED should be a procedure that (ofono call) will call if the
;; outgoing call attempt fails, as (FAILED reason).
;;
;; (dial ...) returns a thunk that the module user can invoke in order
;; to cancel the outgoing call attempt.  This is only valid if done
;; before either ANSWERED or FAILED is called.
(define (dial number answered failed)
  (if vcm-interface
      (let* ((call (car (dbus-call vcm-interface "Dial" number "default")))
	     (call-interface (dbus-interface 'system
					     "org.ofono"
					     call
					     "org.ofono.VoiceCall"))
	     (call-gone #f)
	     (dtmf-digit-received #f))
	(dbus-connect call-interface
		      "PropertyChanged"
		      (lambda (property value)
			(trc 'property-changed property value)
			(cond ((string=? property "State")
			       (case (string->symbol value)
				 ((active)
				  (trc "Call is active")
				  (answered (make-make-active-call call-interface
								   (lambda (arg)
								     (set! call-gone arg))
								   noop)))
				 ((disconnected)
				  (trc "Call is disconnected")
				  (if call-gone
				      ;; Call was active, so use call-gone.
				      (call-gone)
				      ;; Call was still dialing.
				      (failed value))
				  (dbus-interface-release call-interface)))))))
	(lambda ()
	  (dbus-call call-interface "Hangup")))
      (failed "modem not ready")))

(define (make-make-active-call call-interface
			       store-call-gone
			       store-dtmf-digit-received)
  (lambda (call-gone dtmf-digit-received)
    (store-call-gone call-gone)
    (store-dtmf-digit-received dtmf-digit-received)
    (values (lambda ()
	      (dbus-call call-interface "Hangup"))
	    (lambda (digit)
	      (dbus-call vcm-interface "SendTones" digit)))))

;; Until the UI calls set-incoming-call, our default behaviour is to
;; reject an incoming call.
(define (notify-incoming-call number make-active-call reject)
  (reject))

;; (set-incoming-call-proc incoming-call) - Register a procedure to be
;; called if there is an incoming call.
;;
;; When there is an incoming call, (ofono call) will call
;; INCOMING-CALL as (INCOMING-CALL number make-active-call reject).
;; NUMBER is the calling number, as a string, or "Unknown" if not
;; known.  MAKE-ACTIVE-CALL is a procedure with the same purpose and
;; signature as described above under 'dial'.  REJECT is a thunk that
;; the UI can call to reject the incoming call.  The INCOMING-CALL
;; invocation should return a thunk that (ofono call) can call to
;; indicate that the incoming call is no longer available.
;;
;; The anticipated mainline scenario is that the UI indicates to its
;; human user that there is an incoming call (e.g. by playing a ring
;; tone), and that the user indicates, after some interval, if they
;; want to take or reject the call.  During that interval it is
;; possible for the call to disappear (e.g. because the other end
;; stops waiting and hangs up) and this should be indicated to the
;; human user too.
;;
;; To support that scenario, the UI's incoming-call procedure should
;; save off the MAKE-ACTIVE-CALL and REJECT procedures, then
;; immediately return a call-gone thunk.  This allows (ofono call) to
;; call that thunk, if the call disappears, while the user is still
;; deciding whether to answer the call.
;;
;; An alternate scenario - e.g. when a call is handled automatically
;; according to a predefined set of rules - is where the UI knows
;; immediately whether it wants to accept or reject the incoming call.
;; In that case it can call MAKE-ACTIVE-CALL or REJECT from inside the
;; incoming-call procedure, and doesn't need to return a call-gone
;; thunk.
(define (set-incoming-call-proc incoming-call)
  (set! notify-incoming-call incoming-call))

(define vcm-interface #f)

(define (modem-state-hook path properties)
  (if properties
      ;; Modem exists.
      (let ((interfaces (assoc-ref properties "Interfaces")))
	(if (member "org.ofono.VoiceCallManager" interfaces)
	    ;; Voice call interface is available.
	    (if (not vcm-interface)
		;; We haven't already connected to the
		;; voice call interface.
		(begin
		  (set! vcm-interface
			(dbus-interface 'system
					"org.ofono"
					path
					"org.ofono.VoiceCallManager"))
		  (dbus-connect vcm-interface
				"CallAdded"
				(lambda (call properties)
				  (if (string=? (assoc-ref properties "State")
						"incoming")
				      (let ((call-interface
					     (dbus-interface 'system
							     "org.ofono"
							     call
							     "org.ofono.VoiceCall"))
					    (number (or (assoc-ref properties "LineIdentification")
							"Unknown"))
					    (active-call-gone #f)
					    (rejected #f))
					(let* ((unanswered-call-gone
						(notify-incoming-call
						 number
						 (make-make-active-call call-interface
									(lambda (arg)
									  (set! active-call-gone
										arg))
									noop)
						 (lambda ()
						   (dbus-call call-interface "Hangup")
						   (set! rejected #t)))))
					  (or rejected
					      (dbus-connect call-interface
							    "PropertyChanged"
							    (lambda (property value)
							      (cond ((string=? property "State")
								     (case (string->symbol value)
								       ((disconnected)
									(if active-call-gone
									    ;; Call was active.
									    (active-call-gone)
									    ;; Call was still unanswered.
									    (unanswered-call-gone))
									(dbus-interface-release call-interface)))))))))))))))
	    ;; Voice call interface is not available.
	    (set! vcm-interface #f)))
      ;; Modem has disappeared.
      (set! vcm-interface #f)))

(add-modem-state-hook modem-state-hook)
