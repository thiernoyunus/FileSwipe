# Contributing to FileSwipe

Thanks for helping. Keep changes small and easy to try.

## Setup

1. Install [Xcode](https://developer.apple.com/xcode/) (16+ recommended) from the Mac App Store.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you edit `project.yml`:

   ```bash
   brew install xcodegen
   ```

3. Generate the Xcode project and open it:

   ```bash
   cd FileSwipe
   xcodegen generate
   open FileSwipe.xcodeproj
   ```

4. Select the **FileSwipe** scheme → **My Mac** → Run (⌘R).

## Project layout

```
FileSwipe/
  FileSwipeApp.swift          # App entry
  ContentView.swift           # Main window
  Models/FileItem.swift       # One file or folder on disk
  Services/FileQueueManager.swift   # Load folder, keep, trash, undo
  Services/KeyboardPreferences.swift
  Views/SwipeCardView.swift
  Views/FilePreviewView.swift # Images, PDF, video, folders
  Views/KeyboardSettingsView.swift
project.yml                   # XcodeGen project definition
```

## Guidelines

- Prefer clear, everyday wording in the UI.
- Deletes must go to **Trash**, not permanent delete.
- **Keep** must not move or rewrite the file.
- Avoid `HSplitView` and unbounded AppKit views (PDF/video) without fixed sizes — they have crashed the app before.
- Test with a copy of a messy Downloads folder, including images, PDFs, videos, and nested folders.

## Pull requests

1. Describe what a user would notice (not only the code change).
2. Note how you tested (build + manual swipe of a few files).
3. Keep the PR focused.

## License

By contributing, you agree your changes are under the MIT License (see `LICENSE`).
