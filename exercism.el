;;; exercism.el --- Emacs interface for exercism.io -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2022 Ellis Kenyő
;;
;; Author: Ellis Kenyő <me@elken.dev>
;; Maintainer: Ellis Kenyő <me@elken.dev>
;; Created: September 15, 2022
;; Modified: September 15, 2022
;; Version: 0.0.1
;; Homepage: https://github.com/elken/exercism
;; Package-Requires: ((emacs "26.1"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;
;;
;;; Code:

(require 'xdg)
(require 'async)
(require 'request)
(require 'image)

(defgroup exercism nil
  "Settings related to exercism."
  :group 'external
  :link '(url-link :tag "Homepage" "https://github.com/elken/exercism.el"))

(defgroup exercism-faces nil
  "Faces related to exercism."
  :group 'exercism)

(defcustom exercism-api-url "https://exercism.org/api/v2"
  "Default url to query resources for."
  :group 'exercism
  :type 'string)

(defcustom exercism-config-file (expand-file-name "exercism/user.json" (xdg-config-home))
  "Default path to the exercism config file."
  :group 'exercism
  :type 'string)

(defcustom exercism-command (executable-find "exercism")
  "Exercism command to run.
Defaults to first entry in $PATH, can be overridden if required."
  :group 'exercism
  :type 'string)

(defcustom exercism-cache-dir (expand-file-name "exercism" (xdg-cache-home))
  "Directory to use for caching resources."
  :group 'exercism
  :type 'string)

(defface exercism-easy-button
  '((((class color) (min-colors 88))
     :background "#EFFFF1" :foreground "#5FB268")
    (t :background "lightgreen" :foreground "darkgreen"))
  "Face used for easy difficulty exercises."
  :group 'exercism-faces)

(defface exercism-medium-button
  '((((class color) (min-colors 88))
     :background "#F7F5E0" :foreground "#A5A256")
    (t :background "lightyellow" :foreground "darkyellow"))
  "Face used for easy difficulty exercises."
  :group 'exercism-faces)

(defface exercism-hard-button
  '((((class color) (min-colors 88))
     :background "#F4EBE5" :foreground "#CB8D6A")
    (t :background "lightorange" :foreground "lightorange"))
  "Face used for easy difficulty exercises."
  :group 'exercism-faces)

(defvar exercism--icon-urls nil
  "Alist of (slug . iconUrl).")

(defvar exercism-current-track nil
  "Current track to pull exercises for.")

(defvar exercism-track-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<return>") #'exercism-track-view-exercises)
    map)
  "Keymap for `exercism-track-mode'.")

(defvar exercism-exercise-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<return>") #'exercism-download-exercise)
    map)
  "Keymap for `exercism-track-mode'.")

;;;###autoload
(defun exercism-get-config (&optional file-path)
  "Return parsed JSON config.
Optionally check FILE-PATH instead."
  (json-read-file (or file-path exercism-config-file)))

(defun exercism--get-icon (slug)
  "Get an icon for SLUG."
  (let ((path (expand-file-name (format "icons/%s" slug) exercism-cache-dir)))
    (unless (file-exists-p path)
      (mkdir (file-name-directory path) t)
      (async-start
       `(lambda ()
          ,(async-inject-variables "\\`\\(exercism--icon-urls\\)\\'")
          (url-copy-file (cdr (assoc ,slug exercism--icon-urls)) ,path))
       'ignore))
    path))

(defun exercism--endpoint->url (endpoint)
  "Convert an ENDPOINT to a callable url."
  (url-encode-url (mapconcat 'identity
                             `(,exercism-api-url ,endpoint)
                             "/")))

(defun exercism-request (endpoint &optional method)
  "Send a request to ENDPOINT using METHOD.
METHOD defaults to GET and must be a valid argument to `request'."
  (let (result)
    (request
      (exercism--endpoint->url endpoint)
      :type (or method "GET")
      :parser #'json-read
      :headers `(("Authorization" . ,(concat "Bearer " (alist-get 'token (exercism-get-config)))))
      :success (cl-function
                (lambda (&key data &allow-other-keys)
                  (setq result data)))
      :sync t)
    result))

(defun exercism-get-tracks ()
  "Get a list of all tracks."
  (let ((tracks (exercism-request "tracks")))
    (thread-first (alist-get 'tracks tracks)
                  (cl-sort (lambda (lhs rhs)
                             (and (string< (alist-get 'slug lhs) (alist-get 'slug rhs))
                                  (and (alist-get 'is_joined lhs) (alist-get 'is_joined rhs)))))
                  (append nil))))

(defun exercism-get-exercises (language)
  "Get all exercises for a LANGUAGE slug."
  (let ((exercises (exercism-request (format "tracks/%s/exercises" language))))
    (thread-first (alist-get 'exercises exercises)
                  (append nil))))

(defun exercism-download-exercise ()
  "Download a given exercise."
  (interactive)
  (async-start-process
   "exercism-download"
   exercism-command
   (lambda (proc)
     ;; TODO Handle errors
     (message "Exercise cloned"))
   "download"
   (format "--exercise=%s" (tabulated-list-get-id))
   (format "--track=%s" exercism-current-track)))

;;;autoload
(defun exercism ()
  "Open the exercism workspace in Dired."
  (interactive)
  (dired (alist-get 'workspace (exercism-get-config))))

;;;###autoload
(defun exercism-submit-buffer (&optional buffer-or-arg)
  "Submit the current buffer as to exercism.
Pass prefix BUFFER-OR-ARG to prompt for a buffer instead."
  (interactive (when (and current-prefix-arg)
                 (list (read-buffer "Buffer to submit: "))))
  (let ((buffer (buffer-file-name (or buffer-or-arg (current-buffer)))))
    (async-start-process
     "exercism-submit"
     exercism-command
     (lambda (proc)
       ;; TODO Handle submission errors
       (message "Submitted"))
     "submit" buffer)))


;;;###autoload
(defun exercism-track-view-exercises ()
  "Invoked from `exercism-track-mode', load the exercises for a given track."
  (interactive)
  (when (eq major-mode 'exercism-track-mode)
    (setq exercism-current-track (tabulated-list-get-id)))
  (pop-to-buffer (format "*exercism-%s*" exercism-current-track) nil)
  (exercism-exercise-mode))

;;;###autoload
(defun exercism-view-tracks ()
  "View a listing of all current exercism tracks."
  (interactive)
  (pop-to-buffer "*exercism-tracks*" nil)
  (exercism-track-mode))

(define-derived-mode exercism-exercise-mode tabulated-list-mode "exercism-exercise-mode"
  "Major mode for viewing exercism exercises."
  (let* ((exercises (exercism-get-exercises exercism-current-track))
         (title-width (+ 6 (cl-loop for exercise in exercises maximize (length (alist-get 'title exercise))))))
    (setq tabulated-list-format (vector
                                 (list "Exercise" title-width t)
                                 (list "Difficulty" 12 nil)
                                 (list "Description" 0 nil))
          tabulated-list-entries (cl-loop
                                  for exercise in exercises
                                  collect
                                  (progn
                                    (add-to-list 'exercism--icon-urls (cons (alist-get 'slug exercise) (alist-get 'icon_url exercise)))
                                    (let* ((slug (alist-get 'slug exercise))
                                           (icon (exercism--get-icon slug))
                                           (title (alist-get 'title exercise))
                                           (blurb (alist-get 'blurb exercise))
                                           (difficulty (alist-get 'difficulty exercise))
                                           (is-unlocked (not (eq :json-false (alist-get 'is_unlocked exercise))))
                                           (is-recommended (not (eq :json-false (alist-get 'is_recommended exercise))))
                                           (text-face (if is-unlocked 'default 'shadow))
                                           (foreground (face-attribute (intern (format "exercism-%s-button" difficulty)) :foreground))
                                           (background (face-attribute (intern (format "exercism-%s-button" difficulty)) :background)))
                                      (list slug
                                            (vector (concat
                                                     (propertize "  " 'face 'warning)
                                                     (propertize
                                                      " "
                                                      'display
                                                      `(image
                                                        :margin (2 . 2)
                                                        :ascent center
                                                        :width 15
                                                        :type ,(image-type (alist-get 'icon_url exercise))
                                                        :file ,icon))
                                                     (propertize title 'face text-face))
                                                    (propertize
                                                     " "
                                                     'display
                                                     (svg-lib-button "square" (capitalize difficulty) nil
                                                                     :font-weight 900
                                                                     :scale 0.6
                                                                     :radius 6
                                                                     :background background
                                                                     :foreground foreground))
                                                    (propertize blurb 'face text-face))))))

          tabulated-list-padding 4)
    (tabulated-list-init-header)
    (use-local-map exercism-exercise-mode-map)
    (tabulated-list-print t)))

(define-derived-mode exercism-track-mode tabulated-list-mode "exercism-track-mode"
  "Major mode for viewing exercism tracks."
  (let ((tracks (exercism-get-tracks)))
    (setq tabulated-list-format (vector (list "Title" (+ 6 (cl-loop for track in tracks maximize (length (alist-get 'title track)))) t)
                                        (list "Joined" 8 t)
                                        (list "Concepts" 8 nil)
                                        (list "Exercises" 10 nil)
                                        (list "Solutions" 8 nil))
          tabulated-list-entries (cl-loop
                                  for track in tracks
                                  collect
                                  (progn
                                    (add-to-list 'exercism--icon-urls (cons (alist-get 'slug track) (alist-get 'icon_url track)))
                                    (let* ((slug (alist-get 'slug track))
                                           (icon (exercism--get-icon slug))
                                           (title (alist-get 'title track))
                                           (num-concepts (alist-get 'num_concepts track))
                                           (num-exercises (alist-get 'num_exercises track))
                                           (is-joined (alist-get 'is_joined track))
                                           (num-learnt-concepts (alist-get 'num_learnt_concepts track))
                                           (num-completed-exercises (alist-get 'num_completed_exercises track))
                                           (num-solutions (alist-get 'num_solutions track)))
                                      (list slug
                                            (vector (concat
                                                     (propertize
                                                      " "
                                                      'display
                                                      `(image
                                                        :margin (2 . 2)
                                                        :ascent center
                                                        :width 15
                                                        :type ,(image-type (alist-get 'icon_url track))
                                                        :file ,icon))
                                                     title)
                                                    (if is-joined (propertize "" 'face 'success) (propertize "" 'face 'error))
                                                    (concat
                                                     (number-to-string (if (numberp num-learnt-concepts) num-learnt-concepts 0))
                                                     "/"
                                                     (number-to-string (if (numberp num-concepts) num-concepts 0)))
                                                    (concat
                                                     (number-to-string (if (numberp num-completed-exercises) num-completed-exercises 0))
                                                     "/"
                                                     (number-to-string (if (numberp num-exercises) num-exercises 0)))
                                                    (number-to-string (if (numberp num-learnt-concepts)  num-learnt-concepts 0))
                                                    (number-to-string (if (numberp num-solutions)  num-solutions 0)))))))
          tabulated-list-padding 4)
    (tabulated-list-init-header)
    (use-local-map exercism-track-mode-map)

    (tabulated-list-print t)))

(provide 'exercism)
;;; exercism.el ends here