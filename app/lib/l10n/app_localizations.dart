import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ko'), Locale('zh')];

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutNodeMessage.
  ///
  /// In en, this message translates to:
  /// **'About “{title}”: {text}'**
  String aboutNodeMessage(String title, String text);

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @addMainQuest.
  ///
  /// In en, this message translates to:
  /// **'Add a main quest'**
  String get addMainQuest;

  /// No description provided for @addRule.
  ///
  /// In en, this message translates to:
  /// **'Add a rule'**
  String get addRule;

  /// No description provided for @agentAuditor.
  ///
  /// In en, this message translates to:
  /// **'Auditor'**
  String get agentAuditor;

  /// No description provided for @agentChallenger.
  ///
  /// In en, this message translates to:
  /// **'Challenger'**
  String get agentChallenger;

  /// No description provided for @agentCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Check-in'**
  String get agentCheckIn;

  /// No description provided for @agentClarifier.
  ///
  /// In en, this message translates to:
  /// **'Clarifier'**
  String get agentClarifier;

  /// No description provided for @agentGuide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get agentGuide;

  /// No description provided for @agentLinker.
  ///
  /// In en, this message translates to:
  /// **'Linker'**
  String get agentLinker;

  /// No description provided for @agentMaterialFinder.
  ///
  /// In en, this message translates to:
  /// **'Material Finder'**
  String get agentMaterialFinder;

  /// No description provided for @agentNarrator.
  ///
  /// In en, this message translates to:
  /// **'Narrator'**
  String get agentNarrator;

  /// No description provided for @agentPlanner.
  ///
  /// In en, this message translates to:
  /// **'Planner'**
  String get agentPlanner;

  /// No description provided for @agentRecommender.
  ///
  /// In en, this message translates to:
  /// **'Recommender'**
  String get agentRecommender;

  /// No description provided for @agentRecorder.
  ///
  /// In en, this message translates to:
  /// **'Recorder'**
  String get agentRecorder;

  /// No description provided for @agentSyllabusFinder.
  ///
  /// In en, this message translates to:
  /// **'Syllabus Finder'**
  String get agentSyllabusFinder;

  /// No description provided for @answerHint.
  ///
  /// In en, this message translates to:
  /// **'Your answer…'**
  String get answerHint;

  /// No description provided for @askAboutNodeHint.
  ///
  /// In en, this message translates to:
  /// **'Ask about this node…'**
  String get askAboutNodeHint;

  /// No description provided for @askTodaysQuests.
  ///
  /// In en, this message translates to:
  /// **'What should I do today?'**
  String get askTodaysQuests;

  /// No description provided for @attachCourse.
  ///
  /// In en, this message translates to:
  /// **'Attach a course'**
  String get attachCourse;

  /// No description provided for @attempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts'**
  String get attempts;

  /// No description provided for @auditFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get auditFailed;

  /// No description provided for @auditHistory.
  ///
  /// In en, this message translates to:
  /// **'Audit history'**
  String get auditHistory;

  /// No description provided for @auditInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get auditInProgress;

  /// No description provided for @auditPassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get auditPassed;

  /// No description provided for @auditorTagline.
  ///
  /// In en, this message translates to:
  /// **'Asks like a beginner, judges like an expert'**
  String get auditorTagline;

  /// No description provided for @authAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'That email already has an account. Sign in instead.'**
  String get authAlreadyRegistered;

  /// No description provided for @authConfirmEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email first — check your inbox.'**
  String get authConfirmEmailFirst;

  /// No description provided for @authEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get authEnterPassword;

  /// No description provided for @authInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get authInvalidEmail;

  /// No description provided for @authOffline.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection.'**
  String get authOffline;

  /// No description provided for @authPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least {count} characters for your password.'**
  String authPasswordTooShort(int count);

  /// No description provided for @authRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Wait a minute and try again.'**
  String get authRateLimited;

  /// No description provided for @authWrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password.'**
  String get authWrongCredentials;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @backToNode.
  ///
  /// In en, this message translates to:
  /// **'Back to node'**
  String get backToNode;

  /// No description provided for @backToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get backToSignIn;

  /// No description provided for @best.
  ///
  /// In en, this message translates to:
  /// **'Best'**
  String get best;

  /// No description provided for @boss.
  ///
  /// In en, this message translates to:
  /// **'Boss'**
  String get boss;

  /// No description provided for @bossCleared.
  ///
  /// In en, this message translates to:
  /// **'Boss cleared!'**
  String get bossCleared;

  /// No description provided for @callingAuditor.
  ///
  /// In en, this message translates to:
  /// **'Calling the Auditor…'**
  String get callingAuditor;

  /// No description provided for @chapterGrowBody.
  ///
  /// In en, this message translates to:
  /// **'Courses grow under the main quests you set for this year. Everything you prove lights up a point in one sphere you can hold: your life tree.'**
  String get chapterGrowBody;

  /// No description provided for @chapterGrowKicker.
  ///
  /// In en, this message translates to:
  /// **'04 · Grow'**
  String get chapterGrowKicker;

  /// No description provided for @chapterGrowTitle.
  ///
  /// In en, this message translates to:
  /// **'Your whole life, one tree.'**
  String get chapterGrowTitle;

  /// No description provided for @chapterLearnBody.
  ///
  /// In en, this message translates to:
  /// **'Tell the Guide what you want to learn. It finds a real course syllabus and turns it into a tree of ideas you\'ll have to prove, one node at a time.'**
  String get chapterLearnBody;

  /// No description provided for @chapterLearnKicker.
  ///
  /// In en, this message translates to:
  /// **'01 · Learn'**
  String get chapterLearnKicker;

  /// No description provided for @chapterLearnTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick anything. Get a real syllabus.'**
  String get chapterLearnTitle;

  /// No description provided for @chapterProveBody.
  ///
  /// In en, this message translates to:
  /// **'No multiple choice. An Auditor asks like a beginner and judges like an expert, and a Challenger double-checks every pass. Only real understanding turns a node gold.'**
  String get chapterProveBody;

  /// No description provided for @chapterProveKicker.
  ///
  /// In en, this message translates to:
  /// **'02 · Prove'**
  String get chapterProveKicker;

  /// No description provided for @chapterRememberBody.
  ///
  /// In en, this message translates to:
  /// **'Get it wrong and you write down why. It becomes a lesson card, and the Auditor brings it up next time, so the same misconception can\'t sneak past twice.'**
  String get chapterRememberBody;

  /// No description provided for @chapterRememberKicker.
  ///
  /// In en, this message translates to:
  /// **'03 · Remember'**
  String get chapterRememberKicker;

  /// No description provided for @characterSheet.
  ///
  /// In en, this message translates to:
  /// **'Character sheet'**
  String get characterSheet;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// No description provided for @checkInbox.
  ///
  /// In en, this message translates to:
  /// **'Check your inbox'**
  String get checkInbox;

  /// No description provided for @chooseMainQuest.
  ///
  /// In en, this message translates to:
  /// **'Choose a main quest'**
  String get chooseMainQuest;

  /// No description provided for @cleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared!'**
  String get cleared;

  /// No description provided for @clearedBar.
  ///
  /// In en, this message translates to:
  /// **'Cleared {mastered}/{total}'**
  String clearedBar(int mastered, int total);

  /// No description provided for @clearedWithScore.
  ///
  /// In en, this message translates to:
  /// **'Cleared! {score} pts'**
  String clearedWithScore(int score);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @collapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// No description provided for @conditionBar.
  ///
  /// In en, this message translates to:
  /// **'Condition: {state}'**
  String conditionBar(String state);

  /// No description provided for @conditionGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get conditionGood;

  /// No description provided for @conditionLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get conditionLow;

  /// No description provided for @conditionNoRecord.
  ///
  /// In en, this message translates to:
  /// **'No record'**
  String get conditionNoRecord;

  /// No description provided for @confirmLinkSent.
  ///
  /// In en, this message translates to:
  /// **'We sent a link to {email}. Open it to confirm your email, then sign in here.'**
  String confirmLinkSent(String email);

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @course.
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get course;

  /// No description provided for @courses.
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get courses;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @createAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAnAccount;

  /// No description provided for @createYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createYourAccount;

  /// No description provided for @crystalBall.
  ///
  /// In en, this message translates to:
  /// **'Crystal ball'**
  String get crystalBall;

  /// No description provided for @dailyQuests.
  ///
  /// In en, this message translates to:
  /// **'Daily quests'**
  String get dailyQuests;

  /// No description provided for @dotCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get dotCleared;

  /// No description provided for @dotLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get dotLocked;

  /// No description provided for @dotReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get dotReady;

  /// No description provided for @dragToTurn.
  ///
  /// In en, this message translates to:
  /// **'Drag to turn · tap a point'**
  String get dragToTurn;

  /// No description provided for @editUnderCharacter.
  ///
  /// In en, this message translates to:
  /// **'Edit these under My character.'**
  String get editUnderCharacter;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @enterApp.
  ///
  /// In en, this message translates to:
  /// **'Enter Self-Infinity'**
  String get enterApp;

  /// No description provided for @enterEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter your email above first.'**
  String get enterEmailFirst;

  /// No description provided for @errAiFailure.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our side. Please try again.'**
  String get errAiFailure;

  /// No description provided for @errAuditClosed.
  ///
  /// In en, this message translates to:
  /// **'This audit has already ended.'**
  String get errAuditClosed;

  /// No description provided for @errBadRequest.
  ///
  /// In en, this message translates to:
  /// **'You can\'t do that right now.'**
  String get errBadRequest;

  /// No description provided for @errFileUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read any text from this file.'**
  String get errFileUnreadable;

  /// No description provided for @errInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Please check what you entered.'**
  String get errInvalidInput;

  /// No description provided for @errLessonAlreadyMade.
  ///
  /// In en, this message translates to:
  /// **'The lesson card is already made.'**
  String get errLessonAlreadyMade;

  /// No description provided for @errLessonOnlyAfterFail.
  ///
  /// In en, this message translates to:
  /// **'Lesson cards can only be made after a failed audit.'**
  String get errLessonOnlyAfterFail;

  /// No description provided for @errMaxMainQuests.
  ///
  /// In en, this message translates to:
  /// **'You can have at most 3 main quests.'**
  String get errMaxMainQuests;

  /// No description provided for @errNetwork.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection.'**
  String get errNetwork;

  /// No description provided for @errNoNodeReady.
  ///
  /// In en, this message translates to:
  /// **'No node is ready yet. Make a world first.'**
  String get errNoNodeReady;

  /// No description provided for @errNodeLocked.
  ///
  /// In en, this message translates to:
  /// **'This node is locked. Clear its parent first.'**
  String get errNodeLocked;

  /// No description provided for @errNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find that.'**
  String get errNotFound;

  /// No description provided for @errPickGap.
  ///
  /// In en, this message translates to:
  /// **'Pick a gap or misconception to search for.'**
  String get errPickGap;

  /// No description provided for @errSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Your session ended. Please sign in again.'**
  String get errSignedOut;

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// No description provided for @explainHint.
  ///
  /// In en, this message translates to:
  /// **'Explain it in your own words…'**
  String get explainHint;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @getTodaysQuests.
  ///
  /// In en, this message translates to:
  /// **'Get today\'s quests →'**
  String get getTodaysQuests;

  /// No description provided for @goHome.
  ///
  /// In en, this message translates to:
  /// **'Go home'**
  String get goHome;

  /// No description provided for @googleFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start Google sign-in. Please try again.'**
  String get googleFailed;

  /// No description provided for @greetingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue with “{course}”?'**
  String greetingContinue(String course);

  /// No description provided for @greetingNew.
  ///
  /// In en, this message translates to:
  /// **'What shall we learn today?'**
  String get greetingNew;

  /// No description provided for @haveAccount.
  ///
  /// In en, this message translates to:
  /// **'Have an account?'**
  String get haveAccount;

  /// No description provided for @haveAnAccountButton.
  ///
  /// In en, this message translates to:
  /// **'I have an account'**
  String get haveAnAccountButton;

  /// No description provided for @heroHeadline.
  ///
  /// In en, this message translates to:
  /// **'Prove you understand.\nWatch your tree grow.'**
  String get heroHeadline;

  /// No description provided for @heroLead.
  ///
  /// In en, this message translates to:
  /// **'An AI that won\'t let you fake it. You level up only by explaining what you learn, in your own words.'**
  String get heroLead;

  /// No description provided for @heroTagline.
  ///
  /// In en, this message translates to:
  /// **'A learning game you win by explaining'**
  String get heroTagline;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @hintContinue.
  ///
  /// In en, this message translates to:
  /// **'Tap the crystal ball to open your life tree.'**
  String get hintContinue;

  /// No description provided for @hintNew.
  ///
  /// In en, this message translates to:
  /// **'Tell the Guide what you want to learn.'**
  String get hintNew;

  /// No description provided for @hoursShort.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String hoursShort(String hours);

  /// No description provided for @identityPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'I am the type of person who…'**
  String get identityPlaceholder;

  /// No description provided for @identityStem.
  ///
  /// In en, this message translates to:
  /// **'I am the type of person who '**
  String get identityStem;

  /// No description provided for @journal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journal;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @lessonCard.
  ///
  /// In en, this message translates to:
  /// **'Lesson card'**
  String get lessonCard;

  /// No description provided for @lessonCardCreated.
  ///
  /// In en, this message translates to:
  /// **'Lesson card created.'**
  String get lessonCardCreated;

  /// No description provided for @lessonCards.
  ///
  /// In en, this message translates to:
  /// **'Lesson cards'**
  String get lessonCards;

  /// No description provided for @lessons.
  ///
  /// In en, this message translates to:
  /// **'Lessons'**
  String get lessons;

  /// No description provided for @levelBar.
  ///
  /// In en, this message translates to:
  /// **'Lv {level} · {progress}/5'**
  String levelBar(int level, int progress);

  /// No description provided for @lifeTree.
  ///
  /// In en, this message translates to:
  /// **'Life tree'**
  String get lifeTree;

  /// No description provided for @linkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link.'**
  String get linkOpenFailed;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @localModeNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Local mode (no account)'**
  String get localModeNoAccount;

  /// No description provided for @lockedClearNamed.
  ///
  /// In en, this message translates to:
  /// **'Still locked. Clear “{title}” first.'**
  String lockedClearNamed(String title);

  /// No description provided for @lockedClearParent.
  ///
  /// In en, this message translates to:
  /// **'Still locked. Clear the parent node first.'**
  String get lockedClearParent;

  /// No description provided for @mainQuest.
  ///
  /// In en, this message translates to:
  /// **'Main quest'**
  String get mainQuest;

  /// No description provided for @mainQuestPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Teach calculus to a stranger'**
  String get mainQuestPlaceholder;

  /// No description provided for @mainQuests.
  ///
  /// In en, this message translates to:
  /// **'Main quests'**
  String get mainQuests;

  /// No description provided for @makeLessonCard.
  ///
  /// In en, this message translates to:
  /// **'Make a lesson card'**
  String get makeLessonCard;

  /// No description provided for @mapEmptyLine.
  ///
  /// In en, this message translates to:
  /// **'No quest line yet. Tell the Guide what you want to learn.'**
  String get mapEmptyLine;

  /// No description provided for @mapTapNode.
  ///
  /// In en, this message translates to:
  /// **'Tap a node to take it on.'**
  String get mapTapNode;

  /// No description provided for @meals.
  ///
  /// In en, this message translates to:
  /// **'Meals'**
  String get meals;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message…'**
  String get messageHint;

  /// No description provided for @misconception.
  ///
  /// In en, this message translates to:
  /// **'Misconception'**
  String get misconception;

  /// No description provided for @myCharacter.
  ///
  /// In en, this message translates to:
  /// **'My character'**
  String get myCharacter;

  /// No description provided for @navHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get navHowItWorks;

  /// No description provided for @newHere.
  ///
  /// In en, this message translates to:
  /// **'New here?'**
  String get newHere;

  /// No description provided for @newNodesUnlocked.
  ///
  /// In en, this message translates to:
  /// **'New nodes unlocked'**
  String get newNodesUnlocked;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @noAttemptsYet.
  ///
  /// In en, this message translates to:
  /// **'No attempts yet.'**
  String get noAttemptsYet;

  /// No description provided for @noAuditsYet.
  ///
  /// In en, this message translates to:
  /// **'No audits yet.'**
  String get noAuditsYet;

  /// No description provided for @noConversationYet.
  ///
  /// In en, this message translates to:
  /// **'No conversation yet.'**
  String get noConversationYet;

  /// No description provided for @noCourseServesQuest.
  ///
  /// In en, this message translates to:
  /// **'No course serves this quest yet.'**
  String get noCourseServesQuest;

  /// No description provided for @noDescriptionYet.
  ///
  /// In en, this message translates to:
  /// **'No description yet.'**
  String get noDescriptionYet;

  /// No description provided for @noMatchingNode.
  ///
  /// In en, this message translates to:
  /// **'No matching node.'**
  String get noMatchingNode;

  /// No description provided for @noQuestLineYet.
  ///
  /// In en, this message translates to:
  /// **'No quest line yet'**
  String get noQuestLineYet;

  /// No description provided for @node.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get node;

  /// No description provided for @notQuite.
  ///
  /// In en, this message translates to:
  /// **'Not quite.'**
  String get notQuite;

  /// No description provided for @onbBegin.
  ///
  /// In en, this message translates to:
  /// **'Begin'**
  String get onbBegin;

  /// No description provided for @onbBuildFailed.
  ///
  /// In en, this message translates to:
  /// **'I couldn\'t build that world. Try again, or skip for now.'**
  String get onbBuildFailed;

  /// No description provided for @onbBuildIt.
  ///
  /// In en, this message translates to:
  /// **'Build it'**
  String get onbBuildIt;

  /// No description provided for @onbBuildingBody.
  ///
  /// In en, this message translates to:
  /// **'I look for a real syllabus and turn it into a tree of things to prove. This can take a minute.'**
  String get onbBuildingBody;

  /// No description provided for @onbBuildingTitle.
  ///
  /// In en, this message translates to:
  /// **'Building your world…'**
  String get onbBuildingTitle;

  /// No description provided for @onbCourseKicker.
  ///
  /// In en, this message translates to:
  /// **'FIRST COURSE'**
  String get onbCourseKicker;

  /// No description provided for @onbDoneGuide.
  ///
  /// In en, this message translates to:
  /// **'Done.'**
  String get onbDoneGuide;

  /// No description provided for @onbFlipGuide.
  ///
  /// In en, this message translates to:
  /// **'Now flip it.'**
  String get onbFlipGuide;

  /// No description provided for @onbHiGuide.
  ///
  /// In en, this message translates to:
  /// **'Hi, I\'m your Guide.'**
  String get onbHiGuide;

  /// No description provided for @onbIdentityHelper.
  ///
  /// In en, this message translates to:
  /// **'Write it as if it\'s already true.'**
  String get onbIdentityHelper;

  /// No description provided for @onbIdentityKicker.
  ///
  /// In en, this message translates to:
  /// **'IDENTITY'**
  String get onbIdentityKicker;

  /// No description provided for @onbIdentityTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish the sentence.'**
  String get onbIdentityTitle;

  /// No description provided for @onbLearnFirst.
  ///
  /// In en, this message translates to:
  /// **'What do you want to learn first?'**
  String get onbLearnFirst;

  /// No description provided for @onbLearnFirstFor.
  ///
  /// In en, this message translates to:
  /// **'What do you need to learn first for “{quest}”?'**
  String onbLearnFirstFor(String quest);

  /// No description provided for @onbMomentGuide.
  ///
  /// In en, this message translates to:
  /// **'Give me a moment.'**
  String get onbMomentGuide;

  /// No description provided for @onbNeedTopic.
  ///
  /// In en, this message translates to:
  /// **'Tell me a topic, or pick a syllabus file.'**
  String get onbNeedTopic;

  /// No description provided for @onbNodesToProve.
  ///
  /// In en, this message translates to:
  /// **'{count} nodes to prove.'**
  String onbNodesToProve(int count);

  /// No description provided for @onbNodesToProveUnder.
  ///
  /// In en, this message translates to:
  /// **'{count} nodes to prove, under “{quest}”.'**
  String onbNodesToProveUnder(int count, String quest);

  /// No description provided for @onbQuestGuide.
  ///
  /// In en, this message translates to:
  /// **'Pick one quest for this year.'**
  String get onbQuestGuide;

  /// No description provided for @onbQuestHelper.
  ///
  /// In en, this message translates to:
  /// **'You can have up to three. One is plenty to start.'**
  String get onbQuestHelper;

  /// No description provided for @onbQuestKicker.
  ///
  /// In en, this message translates to:
  /// **'MAIN QUEST'**
  String get onbQuestKicker;

  /// No description provided for @onbQuestTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s one goal that moves you toward your win condition?'**
  String get onbQuestTitle;

  /// No description provided for @onbSetUpCharacter.
  ///
  /// In en, this message translates to:
  /// **'Let\'s set up your character.'**
  String get onbSetUpCharacter;

  /// No description provided for @onbSkillsGuide.
  ///
  /// In en, this message translates to:
  /// **'Every quest needs skills.'**
  String get onbSkillsGuide;

  /// No description provided for @onbSkipSetup.
  ///
  /// In en, this message translates to:
  /// **'Skip setup'**
  String get onbSkipSetup;

  /// No description provided for @onbStakesGuide.
  ///
  /// In en, this message translates to:
  /// **'Let\'s start with what\'s at stake.'**
  String get onbStakesGuide;

  /// No description provided for @onbStakesHelper.
  ///
  /// In en, this message translates to:
  /// **'Be honest. This is what you\'re playing against.'**
  String get onbStakesHelper;

  /// No description provided for @onbStakesHint.
  ///
  /// In en, this message translates to:
  /// **'Another year of…'**
  String get onbStakesHint;

  /// No description provided for @onbStakesKicker.
  ///
  /// In en, this message translates to:
  /// **'STAKES'**
  String get onbStakesKicker;

  /// No description provided for @onbStakesTitle.
  ///
  /// In en, this message translates to:
  /// **'A year from now, nothing has changed. What does your life look like?'**
  String get onbStakesTitle;

  /// No description provided for @onbStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String onbStepOf(int step, int total);

  /// No description provided for @onbTopicBody.
  ///
  /// In en, this message translates to:
  /// **'A topic is enough. Got a syllabus? Use the file instead (PDF, TXT or MD).'**
  String get onbTopicBody;

  /// No description provided for @onbTopicHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Calculus'**
  String get onbTopicHint;

  /// No description provided for @onbUseSyllabusFile.
  ///
  /// In en, this message translates to:
  /// **'Use a syllabus file'**
  String get onbUseSyllabusFile;

  /// No description provided for @onbWantToLearn.
  ///
  /// In en, this message translates to:
  /// **'I want to learn {topic}'**
  String onbWantToLearn(String topic);

  /// No description provided for @onbWantToLearnThis.
  ///
  /// In en, this message translates to:
  /// **'I want to learn this'**
  String get onbWantToLearnThis;

  /// No description provided for @onbWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'In Self-Infinity you level up by proving you understand things: you explain them in your own words, and the Auditor decides. A few questions first. One or two sentences each (type them, or tap the mic and say them); you can change everything later.'**
  String get onbWelcomeBody;

  /// No description provided for @onbWhoGuide.
  ///
  /// In en, this message translates to:
  /// **'Who gets there?'**
  String get onbWhoGuide;

  /// No description provided for @onbWinHelper.
  ///
  /// In en, this message translates to:
  /// **'Concrete beats impressive.'**
  String get onbWinHelper;

  /// No description provided for @onbWinHint.
  ///
  /// In en, this message translates to:
  /// **'I can…'**
  String get onbWinHint;

  /// No description provided for @onbWinKicker.
  ///
  /// In en, this message translates to:
  /// **'WIN CONDITION'**
  String get onbWinKicker;

  /// No description provided for @onbWinTitle.
  ///
  /// In en, this message translates to:
  /// **'A year from now, you\'ve won. What does that look like?'**
  String get onbWinTitle;

  /// No description provided for @onbWorldReady.
  ///
  /// In en, this message translates to:
  /// **'Your world “{course}” is ready.'**
  String onbWorldReady(String course);

  /// No description provided for @openLifeTree.
  ///
  /// In en, this message translates to:
  /// **'Open life tree'**
  String get openLifeTree;

  /// No description provided for @openNode.
  ///
  /// In en, this message translates to:
  /// **'Open node'**
  String get openNode;

  /// No description provided for @orDivider.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orDivider;

  /// No description provided for @pageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get pageNotFound;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordWithMin.
  ///
  /// In en, this message translates to:
  /// **'Password (at least {count} characters)'**
  String passwordWithMin(int count);

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'{score} pts'**
  String points(int score);

  /// No description provided for @pointsUnit.
  ///
  /// In en, this message translates to:
  /// **'pts'**
  String get pointsUnit;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @questProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} nodes cleared across {count, plural, =1{1 course} other{{count} courses}}.'**
  String questProgress(int done, int total, int count);

  /// No description provided for @readyToTry.
  ///
  /// In en, this message translates to:
  /// **'Ready to try?'**
  String get readyToTry;

  /// No description provided for @recorderAsk.
  ///
  /// In en, this message translates to:
  /// **'What did you misunderstand?'**
  String get recorderAsk;

  /// No description provided for @recorderTagline.
  ///
  /// In en, this message translates to:
  /// **'Turns a miss into a lesson'**
  String get recorderTagline;

  /// No description provided for @removeMainQuest.
  ///
  /// In en, this message translates to:
  /// **'Remove main quest'**
  String get removeMainQuest;

  /// No description provided for @removeRule.
  ///
  /// In en, this message translates to:
  /// **'Remove rule'**
  String get removeRule;

  /// No description provided for @renameUnderCharacter.
  ///
  /// In en, this message translates to:
  /// **'Rename or remove it under My character.'**
  String get renameUnderCharacter;

  /// No description provided for @replayTutorial.
  ///
  /// In en, this message translates to:
  /// **'Replay the tutorial'**
  String get replayTutorial;

  /// No description provided for @resetLinkSent.
  ///
  /// In en, this message translates to:
  /// **'We sent a password reset link to {email}.'**
  String resetLinkSent(String email);

  /// No description provided for @resources.
  ///
  /// In en, this message translates to:
  /// **'Resources'**
  String get resources;

  /// No description provided for @robotAlt.
  ///
  /// In en, this message translates to:
  /// **'A robot holding your life tree in its palm'**
  String get robotAlt;

  /// No description provided for @rulePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. No phone before the first audit'**
  String get rulePlaceholder;

  /// No description provided for @rules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get rules;

  /// No description provided for @sampleCalculus.
  ///
  /// In en, this message translates to:
  /// **'Calculus'**
  String get sampleCalculus;

  /// No description provided for @sampleClarity.
  ///
  /// In en, this message translates to:
  /// **'Clarity'**
  String get sampleClarity;

  /// No description provided for @sampleDerivatives.
  ///
  /// In en, this message translates to:
  /// **'Derivatives'**
  String get sampleDerivatives;

  /// No description provided for @sampleInference.
  ///
  /// In en, this message translates to:
  /// **'Inference'**
  String get sampleInference;

  /// No description provided for @sampleIntegrals.
  ///
  /// In en, this message translates to:
  /// **'Integrals'**
  String get sampleIntegrals;

  /// No description provided for @sampleLimits.
  ///
  /// In en, this message translates to:
  /// **'Limits'**
  String get sampleLimits;

  /// No description provided for @sampleProbability.
  ///
  /// In en, this message translates to:
  /// **'Probability'**
  String get sampleProbability;

  /// No description provided for @sampleStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get sampleStatistics;

  /// No description provided for @sampleStructure.
  ///
  /// In en, this message translates to:
  /// **'Structure'**
  String get sampleStructure;

  /// No description provided for @sampleWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing'**
  String get sampleWriting;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. {error}'**
  String saveFailed(String error);

  /// No description provided for @scrollHint.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get scrollHint;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchNodesHint.
  ///
  /// In en, this message translates to:
  /// **'Search nodes…'**
  String get searchNodesHint;

  /// No description provided for @seeOutline.
  ///
  /// In en, this message translates to:
  /// **'See the outline →'**
  String get seeOutline;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @serves.
  ///
  /// In en, this message translates to:
  /// **'Serves'**
  String get serves;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @sideQuest.
  ///
  /// In en, this message translates to:
  /// **'Side quest'**
  String get sideQuest;

  /// No description provided for @sideQuestCourse.
  ///
  /// In en, this message translates to:
  /// **'Side quest · Course'**
  String get sideQuestCourse;

  /// No description provided for @sideQuestNone.
  ///
  /// In en, this message translates to:
  /// **'Side quest (none)'**
  String get sideQuestNone;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signInBlurb.
  ///
  /// In en, this message translates to:
  /// **'Sign in to pick up where you left off.'**
  String get signInBlurb;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signUpBlurb.
  ///
  /// In en, this message translates to:
  /// **'Your tree, your lessons and your rules stay in your account.'**
  String get signUpBlurb;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as'**
  String get signedInAs;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @sleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sleep;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrong;

  /// No description provided for @somethingWentWrongShort.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get somethingWentWrongShort;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String sourceLabel(String source);

  /// No description provided for @speakYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Speak your answer'**
  String get speakYourAnswer;

  /// No description provided for @stakes.
  ///
  /// In en, this message translates to:
  /// **'Stakes'**
  String get stakes;

  /// No description provided for @stakesPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'What if nothing changes?'**
  String get stakesPlaceholder;

  /// No description provided for @startAudit.
  ///
  /// In en, this message translates to:
  /// **'Start audit'**
  String get startAudit;

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// No description provided for @stopListening.
  ///
  /// In en, this message translates to:
  /// **'Stop listening'**
  String get stopListening;

  /// No description provided for @takeItOn.
  ///
  /// In en, this message translates to:
  /// **'Take it on'**
  String get takeItOn;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @tourBallBody.
  ///
  /// In en, this message translates to:
  /// **'You in the middle, your quests around you, every skill beyond. Tap the ball on the home screen to open the full tree.'**
  String get tourBallBody;

  /// No description provided for @tourBallKicker.
  ///
  /// In en, this message translates to:
  /// **'YOUR CRYSTAL BALL'**
  String get tourBallKicker;

  /// No description provided for @tourBallTitle.
  ///
  /// In en, this message translates to:
  /// **'Your whole life tree, in one ball.'**
  String get tourBallTitle;

  /// No description provided for @tourLessonsBody.
  ///
  /// In en, this message translates to:
  /// **'When an audit fails, write down what you got wrong. It becomes a lesson card, and the Auditor remembers it next time.'**
  String get tourLessonsBody;

  /// No description provided for @tourLessonsKicker.
  ///
  /// In en, this message translates to:
  /// **'LESSONS'**
  String get tourLessonsKicker;

  /// No description provided for @tourLessonsTitle.
  ///
  /// In en, this message translates to:
  /// **'Every miss becomes a lesson.'**
  String get tourLessonsTitle;

  /// No description provided for @tourNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get tourNext;

  /// No description provided for @tourProveBody.
  ///
  /// In en, this message translates to:
  /// **'Open a point and explain it in your own words. The Auditor asks follow-ups until it\'s sure you understand. Then the point turns gold.'**
  String get tourProveBody;

  /// No description provided for @tourProveKicker.
  ///
  /// In en, this message translates to:
  /// **'PROVE IT'**
  String get tourProveKicker;

  /// No description provided for @tourProveTitle.
  ///
  /// In en, this message translates to:
  /// **'Explain it. The Auditor decides.'**
  String get tourProveTitle;

  /// No description provided for @treeStartsWithYou.
  ///
  /// In en, this message translates to:
  /// **'Your tree starts with you.'**
  String get treeStartsWithYou;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @uploadBadFile.
  ///
  /// In en, this message translates to:
  /// **'Only PDF, TXT or MD files up to 4 MB.'**
  String get uploadBadFile;

  /// No description provided for @uploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload a file'**
  String get uploadFile;

  /// No description provided for @uploadTooMany.
  ///
  /// In en, this message translates to:
  /// **'You can attach up to {count} files.'**
  String uploadTooMany(int count);

  /// No description provided for @uploadedCourseMaterial.
  ///
  /// In en, this message translates to:
  /// **'Uploaded course material'**
  String get uploadedCourseMaterial;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploading;

  /// No description provided for @verdict.
  ///
  /// In en, this message translates to:
  /// **'VERDICT'**
  String get verdict;

  /// No description provided for @verdictCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared.'**
  String get verdictCleared;

  /// No description provided for @verdictNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet.'**
  String get verdictNotYet;

  /// No description provided for @viewFrontPage.
  ///
  /// In en, this message translates to:
  /// **'View the front page'**
  String get viewFrontPage;

  /// No description provided for @viewOutline.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get viewOutline;

  /// No description provided for @viewTree.
  ///
  /// In en, this message translates to:
  /// **'Tree'**
  String get viewTree;

  /// No description provided for @voiceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get voiceListening;

  /// No description provided for @voiceMode.
  ///
  /// In en, this message translates to:
  /// **'Voice mode'**
  String get voiceMode;

  /// No description provided for @voiceModeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice mode isn\'t available on this device.'**
  String get voiceModeUnavailable;

  /// No description provided for @voiceSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking…'**
  String get voiceSpeaking;

  /// No description provided for @voiceTapToTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Tap to turn off voice mode'**
  String get voiceTapToTurnOff;

  /// No description provided for @voiceThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get voiceThinking;

  /// No description provided for @voiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice input isn\'t available on this device.'**
  String get voiceUnavailable;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @whatWasMissing.
  ///
  /// In en, this message translates to:
  /// **'What was missing'**
  String get whatWasMissing;

  /// No description provided for @whatWentWrongHint.
  ///
  /// In en, this message translates to:
  /// **'What did you get wrong?…'**
  String get whatWentWrongHint;

  /// No description provided for @winCondition.
  ///
  /// In en, this message translates to:
  /// **'Win condition'**
  String get winCondition;

  /// No description provided for @winConditionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'What does winning look like?'**
  String get winConditionPlaceholder;

  /// No description provided for @worthSecondLook.
  ///
  /// In en, this message translates to:
  /// **'Worth a second look'**
  String get worthSecondLook;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
