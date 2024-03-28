Custom Tag Importer
====

**Custom Tag Importer**[^1] scans track information from custom tags in your music files. That includes rating tags because a rating tag is basically just a custom tag for ratings.
<br><br>

[⬅️ **Back to the list of all plugins**](https://github.com/AF-1/)
<br><br><br>

## Requirements

- LMS version >= 7.**9**
- LMS database = **SQLite**
<br><br><br>


## Screenshot
<img src="screenshots/cti.gif" width="100%">
<br><br><br>


## Features:
* **Scan track information from custom tags in your music files** to a dedicated LMS database table.
* **Scan rating values** from rating tags in your music files and use them **to set LMS track ratings**.
* Includes a **list of available CTI custom tags and their values**.
* Scan option: **Dump tag names found in your music files to a text file** to see what tags your files include.
* **Automatic rescan**: If you start an LMS rescan, a CTI rescan is performed as part of the LMS rescan (increases LMS rescan time accordingly).
* Create **title formats** using custom tags.
<br><br><br>


## Installation

You should be able to install **Custom Tag Importer** from the LMS main repository (LMS plugin library): **LMS > Settings > Plugins**.<br>

If you want to test a new patch that hasn't made it into a release version yet, you'll have to [install the plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).

It usually takes a few hours for a *new* release to be listed on the LMS plugin page.
<br><br><br>


## Reporting a new issue

If you want to report a new issue, please fill out this [**issue report template**](https://github.com/AF-1/lms-customtagimporter/issues/new?template=bug_report.md&title=%5BISSUE%5D+).
<br><br><br><br>

[^1]:If you want localized strings in your language, please read <a href="https://github.com/AF-1/sobras/wiki/Adding-localization-to-LMS-plugins"><b>this</b></a>. Based on Erland's CustomScan plugin
