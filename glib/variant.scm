
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

(define-module (glib variant)
  #:use-module (system foreign)
  #:use-module (rnrs bytevectors)
  #:export (variant->string
	    FALSE
	    scheme->variant
	    variant->scheme))

(define FALSE 0)

(define gobject (dynamic-link "libgobject-2.0"))
(define glib (dynamic-link "libglib-2.0"))

(dynamic-call "g_type_init" gobject)

(define g_variant_get_child_value
  (pointer->procedure '*
		      (dynamic-func "g_variant_get_child_value" glib)
		      (list '*		; variant
			    int		; index
			    )))

(define g_variant_print
  (pointer->procedure '*
		      (dynamic-func "g_variant_print" glib)
		      (list '*		; variant
			    int		; type annotate
			    )))

(define g_variant_get_type
  (pointer->procedure '*
		      (dynamic-func "g_variant_get_type" glib)
		      (list '*		; variant
			    )))

(define g_variant_get_string
  (pointer->procedure '*
		      (dynamic-func "g_variant_get_string" glib)
		      (list '*		; variant
			    '*		; length
			    )))

(define (variant->string variant)
  (if (null-pointer? variant)
      "(null variant pointer)"
      (string-append (pointer->string (g_variant_get_type variant))
		     ": "
		     (pointer->string (g_variant_print variant FALSE)))))

(define g_variant_new_string
  (pointer->procedure '*
		      (dynamic-func "g_variant_new_string" glib)
		      (list '*		; string
			    )))

(define g_variant_new_boolean
  (pointer->procedure '*
		      (dynamic-func "g_variant_new_boolean" glib)
		      (list int		; boolean
			    )))

(define g_variant_new_tuple
  (pointer->procedure '*
		      (dynamic-func "g_variant_new_tuple" glib)
		      (list '*		; GVariant **
			    int		; num children
			    )))

(define g_variant_n_children
  (pointer->procedure int
		      (dynamic-func "g_variant_n_children" glib)
		      (list '*		; GVariant *
			    )))

(define g_variant_get_variant
  (pointer->procedure '*
		      (dynamic-func "g_variant_get_variant" glib)
		      (list '*		; GVariant *
			    )))

(define g_variant_new_variant
  (pointer->procedure '*
		      (dynamic-func "g_variant_new_variant" glib)
		      (list '*		; GVariant *
			    )))

(define g_variant_get_boolean
  (pointer->procedure int
		      (dynamic-func "g_variant_get_boolean" glib)
		      (list '*		; GVariant *
			    )))

(define g_variant_get_byte
  (pointer->procedure uint8
		      (dynamic-func "g_variant_get_byte" glib)
		      (list '*		; GVariant *
			    )))

(define g_variant_get_uint16
  (pointer->procedure uint16
		      (dynamic-func "g_variant_get_uint16" glib)
		      (list '*		; GVariant *
			    )))

(define g_variant_get_uint32
  (pointer->procedure uint32
		      (dynamic-func "g_variant_get_uint32" glib)
		      (list '*		; GVariant *
			    )))

(define (scheme->variant scheme-value)
  (cond ((null? scheme-value)
	 %null-pointer)
	((list? scheme-value)
	 (g_variant_new_tuple (bytevector->pointer
			       (uint-list->bytevector
				(map pointer-address
				     (map scheme->variant
					  scheme-value))
				(native-endianness)
				(sizeof '*)))
			      (length scheme-value)))
	((string? scheme-value)
	 (g_variant_new_string (string->pointer scheme-value)))
	((boolean? scheme-value)
	 (g_variant_new_variant (g_variant_new_boolean (if scheme-value 1 0))))
	(else
	 (error "No variant conversion yet for this type of value:"
		scheme-value))))

(define (variant->scheme variant)

  (define (variant-children->list variant)
    (map variant->scheme
	    (map (lambda (ii)
		   (g_variant_get_child_value variant ii))
		 (iota (g_variant_n_children variant)))))

  (if (null-pointer? variant)
      *unspecified*
      (let* ((type-string (pointer->string (g_variant_get_type variant)))
	     (type-char (string-ref type-string 0)))
	(case type-char
	  ((#\( #\a)
	   (variant-children->list variant))
	  ((#\{)
	   (let ((pair (variant-children->list variant)))
	     (cons (car pair) (cadr pair))))
	  ((#\s #\o)
	   (pointer->string (g_variant_get_string variant %null-pointer)))
	  ((#\b)
	   (not (zero? (g_variant_get_boolean variant))))
	  ((#\v)
	   (variant->scheme (g_variant_get_variant variant)))
	  ((#\y)
	   (g_variant_get_byte variant))
	  ((#\q)
	   (g_variant_get_uint16 variant))
	  ((#\u)
	   (g_variant_get_uint32 variant))
	  (else
	   (error "No scheme conversion yet for this type of value:"
		  type-string))))))
