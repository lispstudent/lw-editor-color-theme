;;;; Copyright (C) 2013 Paulo Madeira
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at http://mozilla.org/MPL/2.0/.

;;; Interface

(cl:in-package #:cl-user)


(defpackage #:editor-color-theme
  (:use #:cl)
  (:export #:*current-colors*
           #:all-color-themes
           #:color-theme-args
           #:color-theme
           #:define-color-theme
           #:remove-color-theme
           ))

(in-package #:editor-color-theme)


;;; Configuration

;; Default foreground and background colors
(defconstant +default-foreground-color+ :black)
(defconstant +default-background-color+ :white)

(defvar *current-colors* (make-hash-table))

;;; Implementation

(defvar *all-color-themes* (make-hash-table :test 'string=))

(defvar *editor-face-names*
  '(:region
    :show-point-face
    :interactive-input-face
    :highlight
    :non-focus-complete-face
    :font-lock-function-name-face
    :font-lock-comment-face
    :font-lock-type-face
    :font-lock-variable-name-face
    :font-lock-string-face
    :font-lock-keyword-face
    :font-lock-builtin-face
    :compiler-note-highlight
    :compiler-warning-highlight
    :compiler-error-highlight
    :incremental-search-face
    :incremental-search-other-matches-face
    ))

(defvar *all-editor-panes* nil)

(defvar *all-listener-editor-panes* nil)

(defvar *all-collector-panes* nil)
                              

;; (eq (capi:capi-object-name b) 'lw-tools::buffers-list)

(defun all-color-themes ()
  (maphash #'(lambda (key value)
               (declare (ignore value))
               key)
           *all-color-themes*))

(defun color-theme-data (theme-name)
  (multiple-value-bind (data found?)
      (gethash theme-name *all-color-themes*)
    (if found?
        data
        (error "No color theme named ~s found." theme-name))))

(defun color-theme-super-theme-names (theme-name)
  (first (color-theme-data theme-name)))

(defun color-theme-args (theme-name)
  (rest (color-theme-data theme-name)))



(defun update-pane-colors (pane foreground background)
  (setf (capi:simple-pane-foreground pane) foreground)
  (setf (capi:simple-pane-background pane) background)
  
  (let ((recolorize-p (editor::buffer-font-lock-mode-p (capi:editor-pane-buffer pane))))
    (when recolorize-p
      (gp:invalidate-rectangle pane)))
  (values))

(defun update-editor-panes ()
  (let ((foreground (gethash :foreground-color *current-colors*))
        (background (gethash :background-color *current-colors*)))
    (mapcar #'(lambda (pane)
                 (update-pane-colors pane foreground background))
             *all-editor-panes*)))


(defun update-listener-panes ()
  (let ((foreground (gethash :listener-foreground-color *current-colors*))
        (background (gethash :listener-background-color *current-colors*)))
    (mapcar #'(lambda (pane)
                 (update-pane-colors pane foreground background))
             *all-listener-editor-panes*))
  (let ((foreground (gethash :output-foreground-color *current-colors*))
        (background (gethash :output-background-color *current-colors*)))
    (mapcar #'(lambda (pane)
                (update-pane-colors pane foreground background))
            *all-collector-panes*)))



(defun set-color-theme (theme-name)
  (destructuring-bind (&rest color-theme-args
                             &key foreground background
                             listener-foreground
                             listener-background
                             output-foreground
                             output-background
                             &allow-other-keys)
      (color-theme-args theme-name)

    ;; editor foreground and background
    (setf (gethash :foreground-color *current-colors*)
          (or foreground +default-foreground-color+)
          (gethash :background-color *current-colors*)
          (or background +default-background-color+))
    ;; listener foreground and background, uses
    ;; the :background and :foreground if not specified
    (setf (gethash :listener-foreground-color *current-colors*)
          (or listener-foreground
              (gethash :foreground-color *current-colors*)
              +default-foreground-color+)
          (gethash :listener-background-color *current-colors*)
          (or listener-background
              (gethash :background-color *current-colors*)
              +default-background-color+))
    ;; output foreground and background, uses :background and
    ;; :foreground if not specified
    (setf (gethash :output-foreground-color *current-colors*)
          (or output-foreground
              (gethash :foreground-color *current-colors*)
              +default-foreground-color+)
          (gethash :output-background-color *current-colors*)
          (or output-background
              (gethash :background-color *current-colors*)
              +default-background-color+))
    
                                 
    (dolist (name *editor-face-names*)
      (let* ((color-theme-args-for-face (getf color-theme-args name))
             (face-name (intern (string name) '#:editor))
             (face (editor:make-face face-name :if-exists t)))
        (apply 'editor:make-face face-name :if-exists :overwrite
               :documentation (or (getf color-theme-args-for-face :documentation)
                                  (slot-value face 'documentation))
               color-theme-args-for-face))))
  
  theme-name)

(defun color-theme (theme-name)
  (mapc 'set-color-theme (color-theme-super-theme-names theme-name))
  (set-color-theme theme-name)
  
  (update-editor-panes)
  (update-listener-panes)
  
  theme-name)

(defun define-color-theme (theme-name super-theme-names
                           &rest color-theme-args &key &allow-other-keys)
  (unless super-theme-names
    (setf super-theme-names '("default")))
  (dolist (super-theme-name super-theme-names)
    (multiple-value-bind (color-theme-data found?)
        (gethash super-theme-name *all-color-themes*)
      (declare (ignore color-theme-data))
      (unless found?
        (warn "Inherited color theme ~s not defined." super-theme-name))))
  
  (setf (gethash theme-name *all-color-themes*) (list* super-theme-names color-theme-args))
  
  theme-name)

(defun remove-color-theme (theme-name)
  (remhash theme-name *all-color-themes*))

(defun set-editor-pane-colors (pane)
  (typecase pane
     (capi:collector-pane
     (progn
       (pushnew pane *all-collector-panes*)
       (let ((bg-color (gethash :output-background-color *current-colors*))
             (fg-color (gethash :output-foreground-color *current-colors*)))
         (when fg-color
           (setf (capi:simple-pane-foreground pane) fg-color))
         (when bg-color
           (setf (capi:simple-pane-background pane) bg-color)))))
    (capi:editor-pane
     (progn
       (pushnew pane *all-editor-panes*)
       (let ((bg-color (gethash :background-color *current-colors*))
             (fg-color (gethash :foreground-color *current-colors*)))
         (when fg-color
           (setf (capi:simple-pane-foreground pane) fg-color))
         (when bg-color
           (setf (capi:simple-pane-background pane) bg-color)))))))


(defun set-listener-pane-colors (pane)
  (typecase pane
    (capi:editor-pane
     (progn
       (pushnew pane *all-listener-editor-panes*)
       (let ((bg-color (gethash :listener-background-color *current-colors*))
             (fg-color (gethash :listener-foreground-color *current-colors*)))
         (when fg-color
           (setf (capi:simple-pane-foreground pane) fg-color))
         (when bg-color
           (setf (capi:simple-pane-background pane) bg-color)))))))


(defun set-collector-pane-colors (pane)
  ;; only for listener output panes
  ;(when (typep (capi:top-level-interface o) 'lw-tools:listener)
    (pushnew pane *all-collector-panes*)
    (let ((bg-color (gethash :output-background-color *current-colors*))
          (fg-color (gethash :output-foreground-color *current-colors*)))
      (when fg-color
        (setf (capi:simple-pane-foreground pane) fg-color))
      (when bg-color
        (setf (capi:simple-pane-background pane) bg-color))))
   



(lispworks:defadvice ((method capi:interface-display :before (lw-tools:editor))
                      change-editor-colors
                      :before
                      :documentation "Change editor colors.")
    (interface)
  (capi:map-pane-descendant-children interface 'set-editor-pane-colors))


;; we don't have defined capi:interface-display for lw-tools::listener,
;; so nothing to advice. Instead we need to define our own
(sys::without-warning-on-redefinition
  (defmethod capi:interface-display :before ((self lw-tools::listener))
    (capi:map-pane-descendant-children
     self 'set-listener-pane-colors)))

(defvar called nil)

;; capi:collector-pane does'nt have interface-display method called,
;; so we adding the :after constuctor instead
(sys::without-warning-on-redefinition
  (defmethod initialize-instance :after ((self capi:collector-pane) &rest
                                         clos::initargs &key &allow-other-keys)
    (set-collector-pane-colors self)))


;; This makes it "work" after the podium is launched
(defun is-editor-pane-p (obj)
  (and (typep obj 'capi:editor-pane)
       (not (eq obj (hcl:class-prototype (class-of obj))))))

(defun cache-existing-pane (pane)
  (pushnew pane *all-editor-panes*))

(defun cache-if-pane (obj)
  (when (is-editor-pane-p obj)
    (cache-existing-pane obj)))

#+:lispworks-personal-edition
(hcl:sweep-all-objects #'cache-if-pane)


;;; Initial color themes

(define-color-theme "default" ()
  :foreground nil
  :background nil
  :region '(:foreground :color_highlighttext
            :background :color_highlight)
  :show-point-face '(:background :green)
  :interactive-input-face '(:foreground :red3)
  :highlight '(:bold-p t)
  :non-focus-complete-face '(:background :tweak_background)
  :font-lock-function-name-face '(:foreground :blue)
  :font-lock-comment-face '(:foreground :firebrick)
  :font-lock-type-face '(:foreground :forestgreen)
  :font-lock-variable-name-face '(:foreground :darkgoldenrod)
  :font-lock-string-face '(:foreground :rosybrown)
  :font-lock-keyword-face '(:foreground :purple)
  :font-lock-builtin-face '(:foreground :orchid)
  :compiler-note-highlight '(:foreground :magenta)
  :compiler-warning-highlight '(:foreground :orange3)
  :compiler-error-highlight '(:foreground :red)
  :incremental-search-face '(:background :tweak_background)
  :incremental-search-other-matches-face '(:underline-p t))

(define-color-theme "plain" ()
  :foreground nil :background nil
  :region '(:foreground :color_highlighttext
            :background :color_highlight)
  :show-point-face '()
  :interactive-input-face '()
  :highlight '(:bold-p t)
  :non-focus-complete-face '(:background :tweak_background)
  :font-lock-function-name-face '()
  :font-lock-comment-face '()
  :font-lock-type-face '()
  :font-lock-variable-name-face '()
  :font-lock-string-face '()
  :font-lock-keyword-face '()
  :font-lock-builtin-face '()
  :compiler-note-highlight '()
  :compiler-warning-highlight '()
  :compiler-error-highlight '()
  :incremental-search-face '(:background :tweak_background)
  :incremental-search-other-matches-face '(:underline-p t))


(define-color-theme "emacs" ()
  ;; :foreground nil :background nil
  :region '(:foreground :color_highlighttext
            :background :color_highlight)
  :show-point-face '(:background :green)
  :interactive-input-face '(:foreground :red3)
  :highlight '(:bold-p t)
  :non-focus-complete-face '(:background :tweak_background)
  :font-lock-function-name-face '(:foreground :blue)
  :font-lock-comment-face '(:foreground :gray40)
  :font-lock-type-face '(:foreground :forestgreen)
  :font-lock-variable-name-face '(:foreground :darkgoldenrod)
  :font-lock-string-face '(:foreground :rosybrown)
  :font-lock-keyword-face '(:foreground :purple)
  :font-lock-builtin-face '(:foreground :orchid)
  :compiler-note-highlight '(:foreground :magenta)
  :compiler-warning-highlight '(:foreground :orange3)
  :compiler-error-highlight '(:foreground :red)
  :incremental-search-face '(:background :tweak_background)
  :incremental-search-other-matches-face '(:underline-p t))


(define-color-theme "torte" ()
  :foreground (color:make-rgb 0.8s0 0.8s0 0.8s0)
  :background (color:make-rgb 0.0s0 0.0s0 0.0s0)
  :region '(:foreground :color_highlighttext
            :background :color_highlight)
  :show-point-face `(:background ,(color:make-rgb 0.6275s0 0.1255s0 0.9412s0))
  :interactive-input-face '(:foreground :pink)
  :highlight '(:bold-p t)
  :non-focus-complete-face '(:background :tweak_background)
  :font-lock-function-name-face `(:foreground ,(color:make-rgb 0.0s0 1.0s0 1.0s0))
  :font-lock-comment-face `(:foreground ,(color:make-rgb 0.5s0 0.6275s0 1.0s0))
  :font-lock-type-face `(:foreground ,(color:make-rgb 0.5s0 1.0s0 0.5s0))
  :font-lock-variable-name-face `(:foreground ,(color:make-rgb 1.0s0 1.0s0 1.0s0))
  :font-lock-string-face `(:foreground ,(color:make-rgb 1.0s0 0.6275s0 0.6275s0))
  :font-lock-keyword-face `(:foreground ,(color:make-rgb 1.0s0 1.0s0 0.0s0))
  :font-lock-builtin-face `(:foreground ,(color:make-rgb 1.0s0 1.0s0 0.0s0))
  :compiler-note-highlight '(:foreground :magenta)
  :compiler-warning-highlight '(:foreground :orange)
  :compiler-error-highlight '(:foreground :red)
  :incremental-search-face '(:background :tweak_background)
  :incremental-search-other-matches-face '(:underline-p t))



;;; Show presence when loaded
(pushnew :editor-color-theme *features*)
