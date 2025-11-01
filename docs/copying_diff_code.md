# Copying Code From Git Diffs

When reviewing changes in tools like GitHub or GitLab, the right-hand pane in a diff view sometimes only offers options such as **Copy apply in git** or **Copy patch**. Use one of the following approaches to grab the clean source without diff markers:

## 1. Open the Raw File

1. Click the file name at the top of the diff to open the full file view.
2. Use the **Raw** button (GitHub) or **View file** (GitLab) to switch to the plain-text version.
3. Copy the content with `Ctrl+C`/`Cmd+C` and paste it into your editor.

## 2. Download the File

1. In the raw view, use your browser's **Save page as…** option to download the file.
2. Alternatively, click the **Download** button if the hosting platform provides it.

## 3. Copy From Android Studio / IDE

1. Pull the latest changes into your local clone (`git pull`).
2. In Android Studio, open the project and locate the file via the Project tool window (e.g., `lib/user_notifier.dart`).
3. Double-click the file to open it and copy the desired code directly from the editor.

## 4. Check Out the Commit Locally

If you have command-line access:

```bash
git checkout <commit-or-branch>
cat path/to/file.dart
```

This prints the file to the terminal so you can copy or redirect it to another file (e.g., `> /tmp/file.dart`).

These methods provide the plain code without diff markers, allowing you to paste it anywhere you need.

If you are collaborating with the repository’s assistant, you can also ask for the file to be pasted directly into chat or exported as a temporary artifact so it is immediately ready for download.
