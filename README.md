# DDEV Utils

DDEV Utils is a macOS menu bar application that helps you manage your DDEV projects. It provides a quick and easy way to see the status of your projects, and to perform common actions like starting, stopping, and SSH-ing into them.

## Features

*   **Menu Bar Integration:** DDEV Utils lives in your menu bar, so it's always just a click away.
*   **Project Status:** See which of your DDEV projects are running at a glance.
*   **Project Actions:**
    *   Start, stop, and restart projects.
    *   SSH into project containers.
    *   Open project URLs in your browser.
    *   Open project databases in TablePlus.
    *   Enable and disable Xdebug.
*   **Mutagen Status:** View the Mutagen file sync status for your projects.
*   **Favorites:** Mark your most-used projects as favorites for easy access.
*   **Auto-detection:** DDEV Utils automatically detects your DDEV installation.
*   **Customizable:** Choose your preferred terminal application for SSH connections.

## Installation

You can download the latest version of DDEV Utils from the [releases page](https://github.com/REFUZIION/ddev-utils/releases).

1.  Download the `DDEVUtils.dmg` file.
2.  Open the DMG file and drag `DDEVUtils.app` to your `Applications` folder.
3.  Launch DDEVUtils from your `Applications` folder.

## Usage

Click the DDEV Utils icon in your menu bar to see a list of your DDEV projects. From there, you can access the various project actions in the submenus.

### Settings

You can customize the behavior of DDEV Utils by opening the settings window.

*   **DDEV Path:** The path to your DDEV executable. This is usually detected automatically.
*   **Terminal App:** The terminal application to use when SSH-ing into projects. You can choose between Terminal and iTerm.
*   **Hide Stopped Projects:** By default, DDEV Utils shows a submenu with your stopped projects. You can hide this if you only want to see running projects.

## How it Works

DDEV Utils is a native macOS application written in Swift. It works by calling the `ddev` command-line tool and parsing the output. For example, to list your projects, it runs `ddev list --json-output` and then parses the JSON to display the project list.

This means that DDEV Utils is just a convenient wrapper around the `ddev` command, so you can be sure that it's not doing anything that you couldn't do yourself from the terminal.

## Future Enhancements

We are planning to add an in-app update system that will allow DDEV Utils to:

*   Check for new releases on GitHub.
*   Notify you when a new version is available.

This will make it even easier to keep your DDEV Utils installation up-to-date with the latest features and bug fixes.

## Contributing

Contributions are welcome! If you have a feature request or a bug report, please open an issue on the [GitHub repository](https://github.com/REFUZIION/ddev-utils).

If you want to contribute code, you can fork the repository and submit a pull request.

## License

DDEV Utils is open-source software licensed under the [MIT license](https://opensource.org/licenses/MIT).
