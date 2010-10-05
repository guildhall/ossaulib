
(define-module (ossau csv)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 string-fun)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:export (read-csv))

(define (read-csv file-name)
  (let ((s (utf16->string (get-bytevector-all (open-input-file file-name))
			  'little)))

    ;; Discard possible byte order mark.
    (if (and (>= (string-length s) 1)
	     (char=? (string-ref s 0) #\xfeff))
	(set! s (substring s 1)))

    ;; Split out the header line, which tells us how many fields there
    ;; should be in each following line.
    (split-discarding-char #\newline s
      (lambda (header-line rest)
	(let* ((headers (separate-fields-discarding-char #\, header-line list))
	       (nheaders (length headers)))

	  ;; Loop reading data fields.
	  (let loop ((data '())
		     (entry '())
		     (headers-to-read headers)
		     (rest rest))

	    (cond ((null? headers-to-read)
		   (loop (cons (reverse! entry) data)
			 '()
			 headers
			 rest))

		  ((zero? (string-length rest))
		   (reverse! data))

		  ((char=? (string-ref rest 0) #\")
		   (receive (value after)
		       (with-input-from-string rest
			 (lambda ()
			   (values (read)
				   (begin
				     (read-char)
				     (let loop ((chars '())
						(next (read-char)))
				       (if (eof-object? next)
					   (list->string (reverse! chars))
					   (loop (cons next chars)
						 (read-char))))))))
		     (loop data
			   (acons (car headers-to-read) value entry)
			   (cdr headers-to-read)
			   after)))

		  (else
		   (split-discarding-char (if (null? (cdr headers-to-read))
					      #\newline
					      #\,)
					  rest
		     (lambda (value rest)
		       (loop data
			     (acons (car headers-to-read) value entry)
			     (cdr headers-to-read)
			     rest)))))))))))
