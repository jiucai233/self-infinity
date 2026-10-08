// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get about => 'About';

  @override
  String aboutNodeMessage(String title, String text) {
    return 'About “$title”: $text';
  }

  @override
  String get account => 'Account';

  @override
  String get addMainQuest => 'Add a main quest';

  @override
  String get addRule => 'Add a rule';

  @override
  String get agentAuditor => 'Auditor';

  @override
  String get agentChallenger => 'Challenger';

  @override
  String get agentCheckIn => 'Check-in';

  @override
  String get agentClarifier => 'Clarifier';

  @override
  String get agentGuide => 'Guide';

  @override
  String get agentLinker => 'Linker';

  @override
  String get agentMaterialFinder => 'Material Finder';

  @override
  String get agentNarrator => 'Narrator';

  @override
  String get agentPlanner => 'Planner';

  @override
  String get agentRecommender => 'Recommender';

  @override
  String get agentRecorder => 'Recorder';

  @override
  String get agentSyllabusFinder => 'Syllabus Finder';

  @override
  String get answerHint => 'Your answer…';

  @override
  String get askAboutNodeHint => 'Ask about this node…';

  @override
  String get askTodaysQuests => 'What should I do today?';

  @override
  String get attempts => 'Attempts';

  @override
  String get auditFailed => 'Failed';

  @override
  String get auditHistory => 'Audit history';

  @override
  String get auditInProgress => 'In progress';

  @override
  String get auditPassed => 'Passed';

  @override
  String get auditorTagline => 'Asks like a beginner, judges like an expert';

  @override
  String get authAlreadyRegistered => 'That email already has an account. Sign in instead.';

  @override
  String get authConfirmEmailFirst => 'Confirm your email first — check your inbox.';

  @override
  String get authEnterPassword => 'Enter your password.';

  @override
  String get authInvalidEmail => 'Enter a valid email address.';

  @override
  String get authOffline => 'Can\'t reach the server. Check your connection.';

  @override
  String authPasswordTooShort(int count) {
    return 'Use at least $count characters for your password.';
  }

  @override
  String get authRateLimited => 'Too many tries. Wait a minute and try again.';

  @override
  String get authWrongCredentials => 'Wrong email or password.';

  @override
  String get back => 'Back';

  @override
  String get backToNode => 'Back to node';

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get best => 'Best';

  @override
  String get boss => 'Boss';

  @override
  String get bossCleared => 'Boss cleared!';

  @override
  String get callingAuditor => 'Calling the Auditor…';

  @override
  String get chapterGrowBody =>
      'Courses grow under the main quests you set for this year. Everything you prove lights up a point in one sphere you can hold: your life tree.';

  @override
  String get chapterGrowKicker => '04 · Grow';

  @override
  String get chapterGrowTitle => 'Your whole life, one tree.';

  @override
  String get chapterLearnBody =>
      'Tell the Guide what you want to learn. It finds a real course syllabus and turns it into a tree of ideas you\'ll have to prove, one node at a time.';

  @override
  String get chapterLearnKicker => '01 · Learn';

  @override
  String get chapterLearnTitle => 'Pick anything. Get a real syllabus.';

  @override
  String get chapterProveBody =>
      'No multiple choice. An Auditor asks like a beginner and judges like an expert, and a Challenger double-checks every pass. Only real understanding turns a node gold.';

  @override
  String get chapterProveKicker => '02 · Prove';

  @override
  String get chapterRememberBody =>
      'Get it wrong and you write down why. It becomes a lesson card, and the Auditor brings it up next time, so the same misconception can\'t sneak past twice.';

  @override
  String get chapterRememberKicker => '03 · Remember';

  @override
  String get characterSheet => 'Character sheet';

  @override
  String get chatTitle => 'Chat';

  @override
  String get checkInbox => 'Check your inbox';

  @override
  String get chooseMainQuest => 'Choose a main quest';

  @override
  String get cleared => 'Cleared!';

  @override
  String clearedBar(int mastered, int total) {
    return 'Cleared $mastered/$total';
  }

  @override
  String clearedWithScore(int score) {
    return 'Cleared! $score pts';
  }

  @override
  String get close => 'Close';

  @override
  String get collapse => 'Collapse';

  @override
  String conditionBar(String state) {
    return 'Condition: $state';
  }

  @override
  String get conditionGood => 'Good';

  @override
  String get conditionLow => 'Low';

  @override
  String get conditionNoRecord => 'No record';

  @override
  String confirmLinkSent(String email) {
    return 'We sent a link to $email. Open it to confirm your email, then sign in here.';
  }

  @override
  String get continueLabel => 'Continue';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get course => 'Course';

  @override
  String get courses => 'Courses';

  @override
  String get createAccount => 'Create account';

  @override
  String get createAnAccount => 'Create an account';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String get crystalBall => 'Crystal ball';

  @override
  String get dailyQuests => 'Daily quests';

  @override
  String get dotCleared => 'Cleared';

  @override
  String get dotLocked => 'Locked';

  @override
  String get dotReady => 'Ready';

  @override
  String get dragToTurn => 'Drag to turn · tap a point';

  @override
  String get editUnderCharacter => 'Edit these under My character.';

  @override
  String get email => 'Email';

  @override
  String get enterApp => 'Enter Self-Infinity';

  @override
  String get enterEmailFirst => 'Enter your email above first.';

  @override
  String get errAiFailure => 'Something went wrong on our side. Please try again.';

  @override
  String get errAuditClosed => 'This audit has already ended.';

  @override
  String get errBadRequest => 'You can\'t do that right now.';

  @override
  String get errFileUnreadable => 'Couldn\'t read any text from this file.';

  @override
  String get errInvalidInput => 'Please check what you entered.';

  @override
  String get errLessonAlreadyMade => 'The lesson card is already made.';

  @override
  String get errLessonOnlyAfterFail => 'Lesson cards can only be made after a failed audit.';

  @override
  String get errMaxMainQuests => 'You can have at most 3 main quests.';

  @override
  String get errNetwork => 'Can\'t reach the server. Check your connection.';

  @override
  String get errNoNodeReady => 'No node is ready yet. Make a world first.';

  @override
  String get errNodeLocked => 'This node is locked. Clear the nodes before it first.';

  @override
  String get errNotFound => 'We couldn\'t find that.';

  @override
  String get errPickGap => 'Pick a gap or misconception to search for.';

  @override
  String get errSignedOut => 'Your session ended. Please sign in again.';

  @override
  String get expand => 'Expand';

  @override
  String get explainHint => 'Explain it in your own words…';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get getStarted => 'Get started';

  @override
  String get getTodaysQuests => 'Get today\'s quests →';

  @override
  String get goHome => 'Go home';

  @override
  String get googleFailed => 'Couldn\'t start Google sign-in. Please try again.';

  @override
  String greetingContinue(String course) {
    return 'Continue with “$course”?';
  }

  @override
  String get greetingNew => 'What shall we learn today?';

  @override
  String get haveAccount => 'Have an account?';

  @override
  String get haveAnAccountButton => 'I have an account';

  @override
  String get heroHeadline => 'Prove you understand.\nWatch your tree grow.';

  @override
  String get heroLead =>
      'An AI that won\'t let you fake it. You level up only by explaining what you learn, in your own words.';

  @override
  String get heroTagline => 'A learning game you win by explaining';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get hintContinue => 'Tap the crystal ball to open your life tree.';

  @override
  String get hintNew => 'Tell the Guide what you want to learn.';

  @override
  String hoursShort(String hours) {
    return '$hours h';
  }

  @override
  String get identityPlaceholder => 'I am the type of person who…';

  @override
  String get identityStem => 'I am the type of person who ';

  @override
  String get journal => 'Journal';

  @override
  String get language => 'Language';

  @override
  String get lessonCard => 'Lesson card';

  @override
  String get lessonCardCreated => 'Lesson card created.';

  @override
  String get lessonCards => 'Lesson cards';

  @override
  String get lessons => 'Lessons';

  @override
  String levelBar(int level, int progress) {
    return 'Lv $level · $progress/5';
  }

  @override
  String get lifeTree => 'Life tree';

  @override
  String get linkOpenFailed => 'Couldn\'t open the link.';

  @override
  String get loading => 'Loading…';

  @override
  String get localModeNoAccount => 'Local mode (no account)';

  @override
  String lockedClearNamed(String title) {
    return 'Still locked. Clear “$title” first.';
  }

  @override
  String get lockedClearParent => 'Still locked. Clear the nodes before it first.';

  @override
  String get mainQuest => 'Main quest';

  @override
  String get mainQuestPlaceholder => 'e.g. Teach calculus to a stranger';

  @override
  String get mainQuests => 'Main quests';

  @override
  String get makeLessonCard => 'Make a lesson card';

  @override
  String get mapEmptyLine => 'No quest line yet. Tell the Guide what you want to learn.';

  @override
  String get mapTapNode => 'Tap a node to take it on.';

  @override
  String get meals => 'Meals';

  @override
  String get menu => 'Menu';

  @override
  String get messageHint => 'Message…';

  @override
  String get misconception => 'Misconception';

  @override
  String get myCharacter => 'My character';

  @override
  String get navHowItWorks => 'How it works';

  @override
  String get newHere => 'New here?';

  @override
  String get newNodesUnlocked => 'New nodes unlocked';

  @override
  String get next => 'Next';

  @override
  String get noAttemptsYet => 'No attempts yet.';

  @override
  String get noAuditsYet => 'No audits yet.';

  @override
  String get noConversationYet => 'No conversation yet.';

  @override
  String get noDescriptionYet => 'No description yet.';

  @override
  String get noMatchingNode => 'No matching node.';

  @override
  String get noQuestLineYet => 'No quest line yet';

  @override
  String get node => 'Node';

  @override
  String get notQuite => 'Not quite.';

  @override
  String get onbBegin => 'Begin';

  @override
  String get onbBuildFailed => 'I couldn\'t build that world. Try again, or skip for now.';

  @override
  String get onbBuildIt => 'Build it';

  @override
  String get onbBuildingBody =>
      'I look for a real syllabus and turn it into a tree of things to prove. This can take a minute.';

  @override
  String get onbBuildingTitle => 'Building your world…';

  @override
  String get onbCourseKicker => 'FIRST COURSE';

  @override
  String get onbDoneGuide => 'Done.';

  @override
  String get onbFlipGuide => 'Now flip it.';

  @override
  String get onbHiGuide => 'Hi, I\'m your Guide.';

  @override
  String get onbIdentityHelper => 'Write it as if it\'s already true.';

  @override
  String get onbIdentityKicker => 'IDENTITY';

  @override
  String get onbIdentityTitle => 'Finish the sentence.';

  @override
  String get onbLearnFirst => 'What do you want to learn first?';

  @override
  String onbLearnFirstFor(String quest) {
    return 'What do you need to learn first for “$quest”?';
  }

  @override
  String get onbMomentGuide => 'Give me a moment.';

  @override
  String get onbNeedTopic => 'Tell me a topic, or pick a syllabus file.';

  @override
  String onbNodesToProve(int count) {
    return '$count nodes to prove.';
  }

  @override
  String onbNodesToProveUnder(int count, String quest) {
    return '$count nodes to prove, under “$quest”.';
  }

  @override
  String get onbQuestGuide => 'Pick one quest for this year.';

  @override
  String get onbQuestHelper => 'You can have up to three. One is plenty to start.';

  @override
  String get onbQuestKicker => 'MAIN QUEST';

  @override
  String get onbQuestTitle => 'What\'s one goal that moves you toward your win condition?';

  @override
  String get onbSetUpCharacter => 'Let\'s set up your character.';

  @override
  String get onbSkillsGuide => 'Every quest needs skills.';

  @override
  String get onbSkipSetup => 'Skip setup';

  @override
  String get onbStakesGuide => 'Let\'s start with what\'s at stake.';

  @override
  String get onbStakesHelper => 'Be honest. This is what you\'re playing against.';

  @override
  String get onbStakesHint => 'Another year of…';

  @override
  String get onbStakesKicker => 'STAKES';

  @override
  String get onbStakesTitle =>
      'A year from now, nothing has changed. What does your life look like?';

  @override
  String onbStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get onbTopicBody =>
      'A topic is enough. Got a syllabus? Use the file instead (PDF, TXT or MD).';

  @override
  String get onbTopicHint => 'e.g. Calculus';

  @override
  String get onbUseSyllabusFile => 'Use a syllabus file';

  @override
  String onbWantToLearn(String topic) {
    return 'I want to learn $topic';
  }

  @override
  String get onbWantToLearnThis => 'I want to learn this';

  @override
  String get onbWelcomeBody =>
      'In Self-Infinity you level up by proving you understand things: you explain them in your own words, and the Auditor decides. A few questions first. One or two sentences each (type them, or tap the mic and say them); you can change everything later.';

  @override
  String get onbWhoGuide => 'Who gets there?';

  @override
  String get onbWinHelper => 'Concrete beats impressive.';

  @override
  String get onbWinHint => 'I can…';

  @override
  String get onbWinKicker => 'WIN CONDITION';

  @override
  String get onbWinTitle => 'A year from now, you\'ve won. What does that look like?';

  @override
  String onbWorldReady(String course) {
    return 'Your world “$course” is ready.';
  }

  @override
  String get openLifeTree => 'Open life tree';

  @override
  String get openNode => 'Open node';

  @override
  String get orDivider => 'or';

  @override
  String get pageNotFound => 'Page not found';

  @override
  String get password => 'Password';

  @override
  String passwordWithMin(int count) {
    return 'Password (at least $count characters)';
  }

  @override
  String points(int score) {
    return '$score pts';
  }

  @override
  String get pointsUnit => 'pts';

  @override
  String get previous => 'Previous';

  @override
  String get readyToTry => 'Ready to try?';

  @override
  String get recorderAsk => 'What did you misunderstand?';

  @override
  String get recorderTagline => 'Turns a miss into a lesson';

  @override
  String get removeMainQuest => 'Remove main quest';

  @override
  String get removeRule => 'Remove rule';

  @override
  String get replayTutorial => 'Replay the tutorial';

  @override
  String resetLinkSent(String email) {
    return 'We sent a password reset link to $email.';
  }

  @override
  String get resources => 'Resources';

  @override
  String get robotAlt => 'A robot holding your life tree in its palm';

  @override
  String get rulePlaceholder => 'e.g. No phone before the first audit';

  @override
  String get rules => 'Rules';

  @override
  String get sampleCalculus => 'Calculus';

  @override
  String get sampleClarity => 'Clarity';

  @override
  String get sampleDerivatives => 'Derivatives';

  @override
  String get sampleInference => 'Inference';

  @override
  String get sampleIntegrals => 'Integrals';

  @override
  String get sampleLimits => 'Limits';

  @override
  String get sampleProbability => 'Probability';

  @override
  String get sampleStatistics => 'Statistics';

  @override
  String get sampleStructure => 'Structure';

  @override
  String get sampleWriting => 'Writing';

  @override
  String saveFailed(String error) {
    return 'Couldn\'t save. $error';
  }

  @override
  String get scrollHint => 'Scroll';

  @override
  String get search => 'Search';

  @override
  String get searchNodesHint => 'Search nodes…';

  @override
  String get seeOutline => 'See the outline →';

  @override
  String get send => 'Send';

  @override
  String get serves => 'Serves';

  @override
  String get showPassword => 'Show password';

  @override
  String get sideQuest => 'Side quest';

  @override
  String get sideQuestCourse => 'Side quest · Course';

  @override
  String get sideQuestNone => 'Side quest (none)';

  @override
  String get signIn => 'Sign in';

  @override
  String get signInBlurb => 'Sign in to pick up where you left off.';

  @override
  String get signOut => 'Sign out';

  @override
  String get signUpBlurb => 'Your tree, your lessons and your rules stay in your account.';

  @override
  String get signedInAs => 'Signed in as';

  @override
  String get skip => 'Skip';

  @override
  String get sleep => 'Sleep';

  @override
  String get somethingWentWrong => 'Something went wrong. Please try again.';

  @override
  String get somethingWentWrongShort => 'Something went wrong.';

  @override
  String sourceLabel(String source) {
    return 'Source: $source';
  }

  @override
  String get speakYourAnswer => 'Speak your answer';

  @override
  String get stakes => 'Stakes';

  @override
  String get stakesPlaceholder => 'What if nothing changes?';

  @override
  String get startAudit => 'Start audit';

  @override
  String get stats => 'Stats';

  @override
  String get stopListening => 'Stop listening';

  @override
  String get takeItOn => 'Take it on';

  @override
  String get today => 'Today';

  @override
  String get tourBallBody =>
      'You in the middle, your quests around you, every skill beyond. Tap the ball on the home screen to open the full tree.';

  @override
  String get tourBallKicker => 'YOUR CRYSTAL BALL';

  @override
  String get tourBallTitle => 'Your whole life tree, in one ball.';

  @override
  String get tourLessonsBody =>
      'When an audit fails, write down what you got wrong. It becomes a lesson card, and the Auditor remembers it next time.';

  @override
  String get tourLessonsKicker => 'LESSONS';

  @override
  String get tourLessonsTitle => 'Every miss becomes a lesson.';

  @override
  String get tourNext => 'Next';

  @override
  String get tourProveBody =>
      'Open a point and explain it in your own words. The Auditor asks follow-ups until it\'s sure you understand. Then the point turns gold.';

  @override
  String get tourProveKicker => 'PROVE IT';

  @override
  String get tourProveTitle => 'Explain it. The Auditor decides.';

  @override
  String get treeStartsWithYou => 'Your tree starts with you.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get uploadBadFile => 'Only PDF, TXT or MD files up to 4 MB.';

  @override
  String get uploadFile => 'Upload a file';

  @override
  String uploadTooMany(int count) {
    return 'You can attach up to $count files.';
  }

  @override
  String get uploadedCourseMaterial => 'Uploaded course material';

  @override
  String get uploading => 'Uploading…';

  @override
  String get verdict => 'VERDICT';

  @override
  String get verdictCleared => 'Cleared.';

  @override
  String get verdictNotYet => 'Not yet.';

  @override
  String get viewFrontPage => 'View the front page';

  @override
  String get viewOutline => 'Outline';

  @override
  String get viewTree => 'Tree';

  @override
  String get voiceListening => 'Listening…';

  @override
  String get voiceMode => 'Voice mode';

  @override
  String get voiceModeUnavailable => 'Voice mode isn\'t available on this device.';

  @override
  String get voiceSpeaking => 'Speaking…';

  @override
  String get voiceTapToTurnOff => 'Tap to turn off voice mode';

  @override
  String get voiceThinking => 'Thinking…';

  @override
  String get voiceUnavailable => 'Voice input isn\'t available on this device.';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get whatWasMissing => 'What was missing';

  @override
  String get whatWentWrongHint => 'What did you get wrong?…';

  @override
  String get winCondition => 'Win condition';

  @override
  String get winConditionPlaceholder => 'What does winning look like?';

  @override
  String get worthSecondLook => 'Worth a second look';

  @override
  String get you => 'You';

  @override
  String get onbReadingTitle => 'Let me look at that…';

  @override
  String get onbReadingBody => 'Matching it to your main quest.';

  @override
  String get onbPickTitle => 'Where do you want to start?';

  @override
  String get onbPickBody => 'Pick one, or type something more specific.';

  @override
  String get deleteCourse => 'Delete course';

  @override
  String deleteCourseTitle(String course) {
    return 'Delete “$course”?';
  }

  @override
  String get deleteCourseBody => 'It leaves the life tree and its main quest.';

  @override
  String deleteCourseNodes(int count) {
    return 'Also delete its $count nodes, their attempts and lesson cards';
  }

  @override
  String get deleteCourseKeep => 'Left unchecked, your attempts and lesson cards are kept.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get more => 'More';

  @override
  String get devPanel => 'Developer';

  @override
  String get devTitle => 'Audit review';

  @override
  String get devHint => 'Review each verdict below; the first row adds up your reviews.';

  @override
  String get devJudging => 'How well it judges';

  @override
  String get devOverall => 'How audits go';

  @override
  String get devAgreement => 'Agreement';

  @override
  String get devKappa => 'Kappa';

  @override
  String get devTooStrict => 'Too strict';

  @override
  String get devTooLenient => 'Too lenient';

  @override
  String get devLeaked => 'Gave answers';

  @override
  String get devReviewed => 'Reviewed';

  @override
  String get devAudits => 'Audits';

  @override
  String get devPassRate => 'Pass rate';

  @override
  String get devAvgScore => 'Avg score';

  @override
  String get devGapsPerFail => 'Gaps per fail';

  @override
  String get devAnswers => 'Answers per audit';

  @override
  String get devChallenged => 'Challenged';

  @override
  String get devRight => 'Right';

  @override
  String get devGaveAnswer => 'Gave the answer away';

  @override
  String get devNoAudits => 'No finished audits yet.';

  @override
  String get devTranscript => 'Transcript';

  @override
  String get devRefresh => 'Refresh';

  @override
  String get devTabAudits => 'Audits';

  @override
  String get devTabVoice => 'Voice cost';

  @override
  String get devVoiceHint =>
      'At list price. The realtime Guide is billed by tokens, so silence is free; GPT-Live bills every minute the session is open, its backend apart. Audit transcription counts the whole open session, an upper bound.';

  @override
  String get devVoiceGuide => 'Home Guide (realtime)';

  @override
  String get devVoiceAudits => 'Audits (live transcription)';

  @override
  String get devVoiceSessions => 'Sessions';

  @override
  String get devVoiceMinutes => 'Minutes';

  @override
  String get devVoiceCost => 'Cost';

  @override
  String get devVoiceLive => 'On GPT-Live';

  @override
  String get devVoicePerMinute => 'Per minute';

  @override
  String get devVoiceCached => 'From cache';

  @override
  String get devVoiceTurns => 'Turns';

  @override
  String get devNoVoice => 'No live voice sessions yet.';

  @override
  String get breakDown => 'Break it down';

  @override
  String get breakingDown => 'Breaking it down… this can take up to a minute.';

  @override
  String get breakDownFailed => 'Couldn\'t break it down. Try again.';

  @override
  String get unexpandedLine =>
      'Not broken down yet. Break it down to see what\'s inside, or challenge it whole if you already know it.';

  @override
  String get challengeWhole => 'Challenge it whole';

  @override
  String get challengeInProgress => 'Challenge';

  @override
  String get testedOut => 'Cleared by challenge';

  @override
  String get dotUnexpanded => 'Not broken down';

  @override
  String get lifeTitle => 'My life';

  @override
  String get lifeOpen => 'My life →';

  @override
  String lifeDays(int n) {
    return '$n days';
  }

  @override
  String get lifeSleep => 'Sleep';

  @override
  String get lifeFocus => 'Focus';

  @override
  String get lifeStress => 'Stress';

  @override
  String get lifeExercise => 'Exercise';

  @override
  String get lifeWeight => 'Weight';

  @override
  String get lifeAudits => 'Audits';

  @override
  String get lifeOutOf5 => ' / 5';

  @override
  String get lifeDaysSuffix => ' days';

  @override
  String lifeChartTitle(int n) {
    return 'Last $n days';
  }

  @override
  String get lifeNoData => 'Nothing logged in these days yet.';

  @override
  String get lifePatterns => 'Your patterns';

  @override
  String lifePatternsEmpty(int n) {
    return 'Once you have $n days on each side (say, $n with 7 h+ of sleep and $n under 6 h), your own patterns show up here.';
  }

  @override
  String get lifePatternNote => 'Your own days, not a cause: many things differ between them.';

  @override
  String get lifeSleepBetter => 'Slept 7 h+';

  @override
  String get lifeSleepWorse => 'Under 6 h';

  @override
  String get lifeExerciseBetter => 'Exercised';

  @override
  String get lifeExerciseWorse => 'No exercise';

  @override
  String get lifeStressBetter => 'Stress 1–2';

  @override
  String get lifeStressWorse => 'Stress 4–5';

  @override
  String lifeGroupDays(int n) {
    return '$n days';
  }

  @override
  String lifeGroupPassed(int pct, int n) {
    return 'passed $pct% of $n';
  }

  @override
  String get lifeGroupNoAudits => 'no audits';

  @override
  String lifeGroupFocus(String value) {
    return 'focus $value';
  }

  @override
  String get lifeAdvice => 'This week';

  @override
  String get lifeAdviceGet => 'Get advice';

  @override
  String get lifeAdviceAgain => 'New advice';

  @override
  String get lifeAdviceEmpty => 'Three small things for the week, from your own numbers.';

  @override
  String get lifeAdviceFailed => 'Advice isn\'t available right now. Try again.';

  @override
  String lifeAdviceBasedOn(String fact) {
    return 'Based on: $fact';
  }

  @override
  String get lifeLog => 'Days';

  @override
  String get lifeFillIn => 'Fill in a day';

  @override
  String lifeEdit(String date) {
    return 'Edit $date';
  }

  @override
  String get lifeSleepHours => 'Sleep (h)';

  @override
  String get lifeSleepQuality => 'Sleep quality';

  @override
  String get lifeExerciseMinutes => 'Exercise (min)';

  @override
  String get lifeWeightKg => 'Weight (kg)';

  @override
  String get lifeSave => 'Save';

  @override
  String lifeMinutes(int n) {
    return '$n min';
  }

  @override
  String lifeKg(String value) {
    return '$value kg';
  }

  @override
  String lifeAuditsDone(int passed, int n) {
    return '$passed/$n passed';
  }

  @override
  String get lifePrivacy =>
      'Stored in our database. For advice the AI gets averages and patterns, never your days.';
}
