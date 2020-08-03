# seb-mac
Safe Exam Browser for macOS

Open SafeExamBrowser.xcodeproj in a recent version of Xcode (currently 8.0). For building you have to switch off code signing or add your own code signing identities. 

Currently master reflects version 2.1.x. The iOS version of SEB is being developed on branch SEB-iOS and will be merged later with master (as it is a shared Xcode project with both macOS and iOS targets).

All information about Safe Exam Browser you'll find at http://safeexambrowser.org. Search discussions boards if you don't find  information in the manual and SEB How To document (see links on page Support).

For your information: There is only ONE correct way how to spell SEB (all three letters in CAPS). That's why even in camel case classes, methods and symbols should be named SEBFilterTreeController.m for example or SEBUnsavedSettingsAnswerDontSave. If you find SEB written as seb, then that's ok if it's some symbol users will never see. If you find SEB written as Seb, then that is definitely WRONG (unfortunately some of our past developers were not strict about following naming rules)! But both cases are no reason to file a pull request...

## Distribution
- Export an Archive
- Distribute with "Developer ID"
- Upload for notorization
- After you get the confirmation email, export it to the root of the repo.
- run `appdmg dmg.json SafeExamBrowser-2.1.4-intellum.dmg` or similar.


## Testing
1. If supplied with a MeetingID in the permitted applications it should open GoToMeeting with that ID.
1. If a MeetingID is supplied and GoToMeeting is not installed we should show a warning and the quit.
1. If no MeetingID has been supplied GoToMeeting should not be opened.
1. Switch to GoToMeeting and back with `command-tab`. Try the same with finder or another app. 
1. Open Notes in fullscreen mode. Open SEB and then switch to Notes with a four finger swipe. SEB should regain the focus.
1. Click on a `gotomeeting://` link in the browser and make sure it opens GoToMeeting.
