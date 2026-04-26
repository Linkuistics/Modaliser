---
title: Modaliser
---

Modaliser is a Scheme-scriptable modal keyboard system for macOS. Press a leader key to enter a command tree, then type key sequences to execute actions — launch apps, manage windows, run shell commands, search files, and more.

Configuration is written in Scheme via [LispKit](https://github.com/objecthub/swift-lispkit). The config file is code: actions are lambdas, and users can define helper functions inline.

Modaliser is a native Swift macOS app, but the majority of its logic lives in Scheme. On launch, Swift creates a LispKit Scheme runtime and loads `root.scm`, which bootstraps the entire application: activation policy, permissions, status bar, keyboard capture, and user config. The UI is rendered in WKWebView-backed NSPanels controlled from Scheme — an overlay panel for which-key-style hints, and a chooser panel with fuzzy-filtered search and an optional action panel.
