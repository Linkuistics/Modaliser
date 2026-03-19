;; Modaliser configuration
;; This file is evaluated by the Scheme engine at startup.

;; Leader keys (using named constants from DSL library)
(set-leader! 'global F18)
(set-leader! 'local F17)

;; Global command tree
(define-tree 'global
  (key "s" "Safari"
    (lambda () (list 'launch-app "Safari")))

  (key "t" "Terminal"
    (lambda () (list 'launch-app "Terminal")))

  (group "f" "Find"
    (selector "a" "Find Apps"
      'prompt "Find app…"
      'remember "apps"
      'id-field "bundleId")

    (selector "f" "Find File"
      'prompt "Find file…"))

  (group "w" "Windows"
    (key "c" "Center"
      (lambda () (list 'center-window)))
    (key "m" "Maximize"
      (lambda () (list 'maximize-window)))
    (selector "s" "Switch Window"
      'prompt "Select window…")))
