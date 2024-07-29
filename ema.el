;;; ema.el --- ChatGPT based assistant for Emacs
;;; Commentary:
;;; Code:

(require 'url)
(require 'json)
(require 'cl-lib)
(require 'request)
(require 'markdown-mode)

(defgroup ema nil
  "Ema - an abbreviation for Emacs Mindful Assistant. ChatGPT based assistant for Emacs."
  :group 'tools)

(defvar ema-api-endpoint "https://api.openai.com/v1/chat/completions")

(defcustom ema-api-key nil
  "The API key for the OpenAI API."
  :type 'string
  :group 'ema)

(defcustom ema-api-key-env-var "OPENAI_API_KEY"
  "Environment variable to read API key from."
  :type 'string
  :group 'ema)

(defcustom ema-model-name "gpt-4o"
  "OpenAI model to use."
  :type 'string
  :group 'ema)

(defcustom ema-timeout 30
  "OpenAI model to use."
  :type 'integer
  :group 'ema)

(defcustom ema-fallback-system-prompt
  "You are a helpful AI assistant living inside Emacs. Help the user."
  "A fallback system prompt used if the current major mode is not found in `ema-system-prompts-alist`."
  :type 'string
  :group 'ema)

(defcustom ema-generated-buffer-name-prompt
  "Generate descriptive Emacs buffer name based on this content. The name should be lowercase, hyphenated, not too long. Respond with the name only:\n"
  "Prompt used to generate buffer names."
  :type 'string
  :group 'ema)

(defcustom ema-system-prompts-alist
  '((programming-prompt . "You are a helpful AI assistant living inside Emacs, and the perfect programmer. You may only respond with code unless explicitly asked.")
    (writing-prompt . "You are a helpful AI assistant living inside Emacs, and an excellent writing assistant. Respond in markdown concisely and carry out instructions.")
    (chat-prompt . "You are a helpful AI assistant living inside Emacs, and an excellent conversation partner. Respond in markdown and concisely."))
  "An alist that maps system prompt identifiers to actual system prompts."
  :type '(alist :key-type symbol :value-type string)
  :group 'ema)

(defcustom ema-system-prompts-modes-alist
  '((prog-mode . programming-prompt)
    (emacs-lisp-mode . programming-prompt)
    (org-mode . writing-prompt)
    (markdown-mode . writing-prompt)
    (ema-chat-mode . chat-prompt))
  "An alist that maps major modes to system prompt identifiers."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'ema)

;; Chat functions
(defun ema-get-api-key ()
  "Get the API key from `ema-api-key` or the environment variable `OPENAI_API_KEY`."
  (or ema-api-key (getenv ema-api-key-env-var)))

(define-derived-mode ema-chat-mode markdown-mode "ChatGPT"
  "ChatGPT mode"
  (local-set-key (kbd "C-c C-c") 'ema-chat-send-message)
  (local-set-key (kbd "C-c C-r") 'ema-chat-rename-buffer-automatically)
  (run-with-idle-timer 5 nil 'ema-chat-rename-buffer-automatically))

(add-to-list 'auto-mode-alist '("\\.ema\\.md\\'" . ema-chat-mode))

(defun ema-chat-separator (type)
  "Return TYPE chat separator string."
  (let ((datetime (format-time-string "[%Y-%m-%d %H:%M:%S]")))
    (cond ((eq type 'system) (concat "---" datetime " system:\n\n"))
          ((eq type 'user) (concat "\n\n---" datetime " user:\n\n"))
          ((eq type 'assistant) (concat "\n\n---" datetime " assistant:\n\n"))
          (t ""))))

(defvar chat-separator-regex "^-*\\(.*?\\)\\]\\s-*\\(system\\|user\\|assistant\\):$")

(font-lock-add-keywords
 'ema-chat-mode
 '(("^--[-]+\\(.*\\):$" . font-lock-function-name-face)))

(defun ema-get-system-prompt ()
  "Return the system prompt based on the current major mode, or the fallback prompt if the mode is not found."
  (let* ((mode-name (symbol-name major-mode))
         (prompt-identifier (cdr (assoc major-mode ema-system-prompts-modes-alist)))
         (system-prompt (or (cdr (assoc prompt-identifier ema-system-prompts-alist))
                            ema-fallback-system-prompt)))
    (concat system-prompt " Current Emacs major mode: " mode-name ".")))


(defun ema-query-api-alist (messages-alist)
  "Query the OpenAI API with formatted MESSAGES-ALIST.
The JSON should be a list of messages like (:role ,role :content ,content)"
  (let ((out))
    (request
      ema-api-endpoint
      :type "POST"
      :timeout ema-timeout
      :data (json-encode `(:model ,ema-model-name
                                  :messages ,messages-alist))
      :headers `(("Content-Type" . "application/json")
                 ("Authorization" . ,(concat "Bearer " (ema-get-api-key))))
      :sync t
      :parser (lambda ()
                (let ((json-object-type 'hash-table)
                      (json-array-type 'list)
                      (json-key-type 'string))
                  (json-read)))
      :encoding 'utf-8
      :success (cl-function
                (lambda (&key response &allow-other-keys)
                  (let* ((choices (gethash "choices" (request-response-data response)))
                         (msg (gethash "message" (car choices)))
                         (content (gethash "content" msg)))
                    (setq out (replace-regexp-in-string "[“”‘’]" "`" (string-trim content))))))
      :error (cl-function (lambda (&rest args &key error-thrown &allow-other-keys)
                            (message "Error: %S" error-thrown))))
    out))

(defun ema-query-api (prompt)
  "Sends user query PROMPT to API."
  (ema-query-api-alist `(((role . "user") (content . ,prompt)))))

(defun ema-generate-buffer-name (&optional prefix temp)
  "Generate a buffer name based on the first characters of the buffer.
If PREFIX, adds the prefix in front of the name.
If TEMP, adds asterisks to the name."
  (save-excursion
    (goto-char (point-min))
    (when (string= (buffer-substring-no-properties (point-min) (min 16 (point-max)))
                   (string-trim (ema-chat-separator 'system)))
      (search-forward (string-trim (ema-chat-separator 'user)) nil t))
    (let ((name
           (ema-query-api-alist
            `(((role . "system") (content . ,ema-generated-buffer-name-prompt))
              ((role . "user") (content . ,(buffer-substring-no-properties (point) (min (+ 1200 (point)) (point-max)))))))))
      (cond ((and prefix temp) (concat "*" prefix name "*"))
            (prefix (concat prefix "-" name))
            (temp (concat "*" name "*"))
            (t name)))))

(defun ema-chat-rename-buffer-automatically ()
  "Rename a buffer based on its contents.
Only when the buffer isn't visiting a file."
  (interactive)
  (when (not buffer-file-name)
    (let ((new-name (ema-generate-buffer-name "ema-chatgpt:" 't)))
      (unless (get-buffer new-name)
        (rename-buffer new-name)))))

;;;###autoload
(defun ema-start-chat (prompt)
  "Start a chat with PROMPT.
If the universal argument is given, use the current buffer mode to set the system prompt."
  (interactive "sPrompt: ")
  (let*
      ((selected-region (and (use-region-p) (buffer-substring-no-properties (mark) (point))))
       (num-windows (count-windows)))
    (deactivate-mark)
    (if (= num-windows 1)
        (split-window-vertically))
    (with-selected-window (display-buffer (get-buffer-create "*ema-response*"))
      (erase-buffer)
      (ema-chat-mode)
      (insert
       (let*
           ((chat-string (concat
                         (ema-chat-separator 'system)
                         (ema-get-system-prompt)
                         (ema-chat-separator 'user)
                         prompt
                         (and selected-region (concat "\n\n"selected-region)))))
           (concat
            chat-string
            (ema-chat-separator 'assistant)
            (ema-query-api-alist (ema-chat-string-to-alist chat-string)))))
      (ema-chat-insert-user-prompt))))


(defun ema-chat-insert-user-prompt ()
  "Add dividing lines and user input prompt to a buffer."
  (with-current-buffer (buffer-name)
    (goto-char (point-max))
    (insert (ema-chat-separator 'user))
    (goto-char (point-max))))

(defun ema-chat-string-to-alist (chat-string)
  "Transforms CHAT-STRING into a JSON array of chat messages."
  (let ((messages '()))
    (with-temp-buffer
      (insert chat-string)
      (goto-char (point-min))
      (while (search-forward-regexp chat-separator-regex nil t)
        (let* ((role (match-string-no-properties 2))
               (start (point))
               (end (when (save-excursion (search-forward-regexp chat-separator-regex nil t))
                      (match-beginning 0)))
               (content (buffer-substring-no-properties start (or end (point-max)))))
          (push `((role . ,role) (content . ,(string-trim content))) messages))))
    (reverse messages)))

(defun ema-chat-buffer-to-alist ()
  "Transforms the current buffer into a JSON array of chat messages."
  (interactive)
  (let ((chat-string (buffer-string)))
    (ema-chat-string-to-alist chat-string)))


(defun ema-chat-send-message ()
  "Send a message to chatgpt, to be used in a ema-chat buffer."
  (interactive)
  (save-excursion
    (let* ((inserted-text (concat
                           (ema-chat-separator 'assistant)
                           (ema-query-api-alist (ema-chat-buffer-to-alist)))))
      (goto-char (point-max))
      (insert inserted-text)
      (ema-chat-insert-user-prompt)))
  (goto-char (point-max)))


;;;###autoload
(defun ema-replace-region (prompt)
  "Send the selected region to the OpenAI API with PROMPT and replace the region with the output."
  (interactive "sPrompt: ")
  (let ((selected-region (buffer-substring-no-properties (mark) (point))))
    (deactivate-mark)
    (let ((modified-region (ema-query-api (concat (ema-get-system-prompt) "\n" prompt " " selected-region))))
      (delete-region (mark) (point))
      (insert modified-region))))


;;;###autoload
(defun ema-insert (prompt)
  "Insert text after the selected region or point.
Send the selected region / custom PROMPT to the OpenAI API with PROMPT
and insert the output before/after the region or at point."
  (interactive "sPrompt: ")
  (save-excursion
    (let ((selected-region (if (region-active-p)
                               (buffer-substring-no-properties (mark) (point))
                             nil)))
      (deactivate-mark)
      (let* ((query (concat
                     (ema-get-system-prompt)
                     "\nUser input:\n"
                     prompt
                     (when selected-region (concat "\n" " " selected-region "\n"))))
             (inserted-text (ema-query-api query)))
        (when selected-region
          (goto-char (if (< (mark) (point))
                         (point)
                       (mark))))
        (insert inserted-text)))))

(provide 'ema)

;;; ema.el ends here
