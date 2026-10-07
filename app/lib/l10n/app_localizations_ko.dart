// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get about => '소개';

  @override
  String aboutNodeMessage(String title, String text) {
    return '“$title”에 대해: $text';
  }

  @override
  String get account => '계정';

  @override
  String get addMainQuest => '메인 퀘스트 추가';

  @override
  String get addRule => '규칙 추가';

  @override
  String get agentAuditor => '심사관';

  @override
  String get agentChallenger => '반론자';

  @override
  String get agentCheckIn => '체크인';

  @override
  String get agentClarifier => '질문자';

  @override
  String get agentGuide => '가이드';

  @override
  String get agentLinker => '연결자';

  @override
  String get agentMaterialFinder => '자료 탐색자';

  @override
  String get agentNarrator => '내레이터';

  @override
  String get agentPlanner => '플래너';

  @override
  String get agentRecommender => '추천자';

  @override
  String get agentRecorder => '기록자';

  @override
  String get agentSyllabusFinder => '강의계획 탐색자';

  @override
  String get answerHint => '답변…';

  @override
  String get askAboutNodeHint => '이 노드에 대해 물어보세요…';

  @override
  String get askTodaysQuests => '오늘 뭘 하면 좋을까?';

  @override
  String get attachCourse => '강좌 연결하기';

  @override
  String get attempts => '시도';

  @override
  String get auditFailed => '미통과';

  @override
  String get auditHistory => '심사 기록';

  @override
  String get auditInProgress => '진행 중';

  @override
  String get auditPassed => '통과';

  @override
  String get auditorTagline => '초보자처럼 묻고, 전문가처럼 판단해요';

  @override
  String get authAlreadyRegistered => '이미 가입된 이메일이에요. 로그인해 주세요.';

  @override
  String get authConfirmEmailFirst => '먼저 이메일 인증을 해 주세요. 받은편지함을 확인해 보세요.';

  @override
  String get authEnterPassword => '비밀번호를 입력하세요.';

  @override
  String get authInvalidEmail => '올바른 이메일 주소를 입력하세요.';

  @override
  String get authOffline => '서버에 연결할 수 없어요. 인터넷 연결을 확인하세요.';

  @override
  String authPasswordTooShort(int count) {
    return '비밀번호는 $count자 이상이어야 해요.';
  }

  @override
  String get authRateLimited => '시도 횟수가 너무 많아요. 1분 뒤에 다시 해 보세요.';

  @override
  String get authWrongCredentials => '이메일 또는 비밀번호가 맞지 않아요.';

  @override
  String get back => '뒤로';

  @override
  String get backToNode => '노드로 돌아가기';

  @override
  String get backToSignIn => '로그인으로 돌아가기';

  @override
  String get best => '최고 점수';

  @override
  String get boss => '보스';

  @override
  String get bossCleared => '보스 클리어!';

  @override
  String get callingAuditor => '심사관을 부르는 중…';

  @override
  String get chapterGrowBody =>
      '강좌는 올해 정한 메인 퀘스트 아래에서 자라요. 증명한 모든 것이 손에 쥘 수 있는 구슬 속 점 하나를 밝혀요. 그게 당신의 인생 나무예요.';

  @override
  String get chapterGrowKicker => '04 · 성장하기';

  @override
  String get chapterGrowTitle => '당신의 삶 전체가, 나무 한 그루.';

  @override
  String get chapterLearnBody => '배우고 싶은 걸 가이드에게 말하세요. 실제 강의계획서를 찾아, 하나씩 증명해야 할 개념의 나무로 바꿔 줘요.';

  @override
  String get chapterLearnKicker => '01 · 배우기';

  @override
  String get chapterLearnTitle => '무엇이든 고르면, 진짜 강의계획서가 와요.';

  @override
  String get chapterProveBody =>
      '객관식은 없어요. 심사관은 초보자처럼 묻고 전문가처럼 판단하고, 반론자가 모든 통과를 다시 확인해요. 정말 이해해야만 노드가 금색으로 바뀌어요.';

  @override
  String get chapterProveKicker => '02 · 증명하기';

  @override
  String get chapterRememberBody =>
      '틀리면 왜 틀렸는지 적어요. 그게 교훈 카드가 되고, 심사관이 다음에 꼭 꺼내 와요. 같은 오개념이 두 번 빠져나갈 순 없어요.';

  @override
  String get chapterRememberKicker => '03 · 기억하기';

  @override
  String get characterSheet => '캐릭터 시트';

  @override
  String get chatTitle => '대화';

  @override
  String get checkInbox => '받은편지함을 확인하세요';

  @override
  String get chooseMainQuest => '메인 퀘스트 선택';

  @override
  String get cleared => '클리어!';

  @override
  String clearedBar(int mastered, int total) {
    return '클리어 $mastered/$total';
  }

  @override
  String clearedWithScore(int score) {
    return '클리어! $score점';
  }

  @override
  String get close => '닫기';

  @override
  String get collapse => '접기';

  @override
  String conditionBar(String state) {
    return '컨디션: $state';
  }

  @override
  String get conditionGood => '좋음';

  @override
  String get conditionLow => '낮음';

  @override
  String get conditionNoRecord => '기록 없음';

  @override
  String confirmLinkSent(String email) {
    return '$email(으)로 링크를 보냈어요. 링크를 열어 이메일을 인증한 뒤 여기서 로그인하세요.';
  }

  @override
  String get continueLabel => '계속';

  @override
  String get continueWithGoogle => 'Google로 계속하기';

  @override
  String get course => '강좌';

  @override
  String get courses => '강좌';

  @override
  String get createAccount => '계정 만들기';

  @override
  String get createAnAccount => '계정 만들기';

  @override
  String get createYourAccount => '계정 만들기';

  @override
  String get crystalBall => '수정 구슬';

  @override
  String get dailyQuests => '일일 퀘스트';

  @override
  String get dotCleared => '클리어';

  @override
  String get dotLocked => '잠김';

  @override
  String get dotReady => '도전 가능';

  @override
  String get dragToTurn => '드래그해서 돌리기 · 점 탭하기';

  @override
  String get editUnderCharacter => '\'내 캐릭터\'에서 수정할 수 있어요.';

  @override
  String get email => '이메일';

  @override
  String get enterApp => 'Self-Infinity 시작하기';

  @override
  String get enterEmailFirst => '먼저 위에 이메일을 입력하세요.';

  @override
  String get errAiFailure => '저희 쪽에서 문제가 생겼어요. 다시 시도해 주세요.';

  @override
  String get errAuditClosed => '이 심사는 이미 끝났어요.';

  @override
  String get errBadRequest => '지금은 그렇게 할 수 없어요.';

  @override
  String get errFileUnreadable => '이 파일에서 글자를 읽을 수 없었어요.';

  @override
  String get errInvalidInput => '입력한 내용을 확인해 주세요.';

  @override
  String get errLessonAlreadyMade => '교훈 카드를 이미 만들었어요.';

  @override
  String get errLessonOnlyAfterFail => '교훈 카드는 심사에서 떨어졌을 때만 만들 수 있어요.';

  @override
  String get errMaxMainQuests => '메인 퀘스트는 최대 3개까지예요.';

  @override
  String get errNetwork => '서버에 연결할 수 없어요. 인터넷 연결을 확인하세요.';

  @override
  String get errNoNodeReady => '아직 도전할 노드가 없어요. 먼저 세계를 만들어 보세요.';

  @override
  String get errNodeLocked => '이 노드는 잠겨 있어요. 상위 노드를 먼저 클리어하세요.';

  @override
  String get errNotFound => '찾을 수 없어요.';

  @override
  String get errPickGap => '검색할 빈틈이나 오개념을 골라 주세요.';

  @override
  String get errSignedOut => '세션이 끝났어요. 다시 로그인해 주세요.';

  @override
  String get expand => '펼치기';

  @override
  String get explainHint => '자기 말로 설명해 보세요…';

  @override
  String get forgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get getStarted => '시작하기';

  @override
  String get getTodaysQuests => '오늘의 퀘스트 받기 →';

  @override
  String get goHome => '홈으로';

  @override
  String get googleFailed => 'Google 로그인을 시작하지 못했어요. 다시 시도해 주세요.';

  @override
  String greetingContinue(String course) {
    return '“$course” 이어서 할까요?';
  }

  @override
  String get greetingNew => '오늘은 뭘 배워 볼까요?';

  @override
  String get haveAccount => '계정이 있나요?';

  @override
  String get haveAnAccountButton => '계정이 있어요';

  @override
  String get heroHeadline => '이해했다는 걸 증명하고,\n나무가 자라는 걸 지켜보세요.';

  @override
  String get heroLead => '아는 척은 통하지 않는 AI. 배운 걸 자기 말로 설명해야만 레벨이 올라요.';

  @override
  String get heroTagline => '설명해야 이기는 학습 게임';

  @override
  String get hidePassword => '비밀번호 숨기기';

  @override
  String get hintContinue => '수정 구슬을 눌러 인생 나무를 열어 보세요.';

  @override
  String get hintNew => '배우고 싶은 걸 가이드에게 말해 보세요.';

  @override
  String hoursShort(String hours) {
    return '$hours시간';
  }

  @override
  String get identityPlaceholder => '나는 …하는 사람이다';

  @override
  String get identityStem => '나는 ';

  @override
  String get journal => '일기';

  @override
  String get language => '언어';

  @override
  String get lessonCard => '교훈 카드';

  @override
  String get lessonCardCreated => '교훈 카드를 만들었어요.';

  @override
  String get lessonCards => '교훈 카드';

  @override
  String get lessons => '교훈';

  @override
  String levelBar(int level, int progress) {
    return 'Lv $level · $progress/5';
  }

  @override
  String get lifeTree => '인생 나무';

  @override
  String get linkOpenFailed => '링크를 열 수 없어요.';

  @override
  String get loading => '불러오는 중…';

  @override
  String get localModeNoAccount => '로컬 모드 (계정 없음)';

  @override
  String lockedClearNamed(String title) {
    return '아직 잠겨 있어요. “$title”부터 클리어하세요.';
  }

  @override
  String get lockedClearParent => '아직 잠겨 있어요. 상위 노드를 먼저 클리어하세요.';

  @override
  String get mainQuest => '메인 퀘스트';

  @override
  String get mainQuestPlaceholder => '예: 처음 보는 사람에게 미적분 가르치기';

  @override
  String get mainQuests => '메인 퀘스트';

  @override
  String get makeLessonCard => '교훈 카드 만들기';

  @override
  String get mapEmptyLine => '아직 퀘스트 라인이 없어요. 배우고 싶은 걸 가이드에게 말해 보세요.';

  @override
  String get mapTapNode => '노드를 탭해서 도전해 보세요.';

  @override
  String get meals => '식사';

  @override
  String get menu => '메뉴';

  @override
  String get messageHint => '메시지…';

  @override
  String get misconception => '오개념';

  @override
  String get myCharacter => '내 캐릭터';

  @override
  String get navHowItWorks => '작동 방식';

  @override
  String get newHere => '처음이신가요?';

  @override
  String get newNodesUnlocked => '새 노드가 열렸어요';

  @override
  String get next => '다음';

  @override
  String get noAttemptsYet => '아직 시도 기록이 없어요.';

  @override
  String get noAuditsYet => '아직 심사 기록이 없어요.';

  @override
  String get noConversationYet => '아직 대화가 없어요.';

  @override
  String get noCourseServesQuest => '아직 이 퀘스트에 연결된 강좌가 없어요.';

  @override
  String get noDescriptionYet => '아직 설명이 없어요.';

  @override
  String get noMatchingNode => '일치하는 노드가 없어요.';

  @override
  String get noQuestLineYet => '아직 퀘스트 라인이 없어요';

  @override
  String get node => '노드';

  @override
  String get notQuite => '아직 조금 부족해요.';

  @override
  String get onbBegin => '시작하기';

  @override
  String get onbBuildFailed => '그 세계를 만들지 못했어요. 다시 해 보거나 일단 건너뛰세요.';

  @override
  String get onbBuildIt => '만들기';

  @override
  String get onbBuildingBody => '실제 강의계획서를 찾아서 증명할 것들의 나무로 바꿔요. 1분쯤 걸릴 수 있어요.';

  @override
  String get onbBuildingTitle => '당신의 세계를 만드는 중…';

  @override
  String get onbCourseKicker => '첫 강좌';

  @override
  String get onbDoneGuide => '다 됐어요.';

  @override
  String get onbFlipGuide => '이제 뒤집어 볼까요.';

  @override
  String get onbHiGuide => '안녕하세요, 저는 가이드예요.';

  @override
  String get onbIdentityHelper => '이미 사실인 것처럼 써 보세요.';

  @override
  String get onbIdentityKicker => '정체성';

  @override
  String get onbIdentityTitle => '문장을 완성해 보세요.';

  @override
  String get onbLearnFirst => '무엇부터 배우고 싶어요?';

  @override
  String onbLearnFirstFor(String quest) {
    return '“$quest” 퀘스트를 위해 먼저 뭘 배워야 할까요?';
  }

  @override
  String get onbMomentGuide => '잠깐만요.';

  @override
  String get onbNeedTopic => '주제를 알려 주거나 강의계획서 파일을 골라 주세요.';

  @override
  String onbNodesToProve(int count) {
    return '증명할 노드 $count개.';
  }

  @override
  String onbNodesToProveUnder(int count, String quest) {
    return '“$quest” 아래 증명할 노드 $count개.';
  }

  @override
  String get onbQuestGuide => '올해의 퀘스트를 하나 골라요.';

  @override
  String get onbQuestHelper => '최대 세 개까지 둘 수 있어요. 시작은 하나면 충분해요.';

  @override
  String get onbQuestKicker => '메인 퀘스트';

  @override
  String get onbQuestTitle => '승리 조건에 가까워지게 해 줄 목표 하나는 뭔가요?';

  @override
  String get onbSetUpCharacter => '캐릭터를 만들어 볼까요.';

  @override
  String get onbSkillsGuide => '모든 퀘스트엔 스킬이 필요해요.';

  @override
  String get onbSkipSetup => '설정 건너뛰기';

  @override
  String get onbStakesGuide => '먼저 걸린 것부터 이야기해요.';

  @override
  String get onbStakesHelper => '솔직하게 써 주세요. 이게 당신이 맞서 싸울 상대예요.';

  @override
  String get onbStakesHint => '또 1년 동안…';

  @override
  String get onbStakesKicker => '걸린 것';

  @override
  String get onbStakesTitle => '1년 뒤, 아무것도 바뀌지 않았어요. 당신의 삶은 어떤 모습인가요?';

  @override
  String onbStepOf(int step, int total) {
    return '$total단계 중 $step단계';
  }

  @override
  String get onbTopicBody => '주제만 있어도 돼요. 강의계획서가 있다면 파일을 쓰세요 (PDF, TXT, MD).';

  @override
  String get onbTopicHint => '예: 미적분';

  @override
  String get onbUseSyllabusFile => '강의계획서 파일 사용';

  @override
  String onbWantToLearn(String topic) {
    return '$topic 배우고 싶어요';
  }

  @override
  String get onbWantToLearnThis => '이거 배우고 싶어요';

  @override
  String get onbWelcomeBody =>
      'Self-Infinity에서는 이해했다는 걸 증명해야 레벨이 올라요. 자기 말로 설명하면 심사관이 판단해요. 먼저 몇 가지만 물어볼게요. 각각 한두 문장이면 돼요(직접 쓰거나 마이크를 눌러 말해도 돼요). 나중에 전부 바꿀 수 있어요.';

  @override
  String get onbWhoGuide => '누가 거기까지 갈까요?';

  @override
  String get onbWinHelper => '거창한 것보다 구체적인 게 좋아요.';

  @override
  String get onbWinHint => '나는 …할 수 있다';

  @override
  String get onbWinKicker => '승리 조건';

  @override
  String get onbWinTitle => '1년 뒤, 당신이 이겼어요. 어떤 모습인가요?';

  @override
  String onbWorldReady(String course) {
    return '“$course” 세계가 준비됐어요.';
  }

  @override
  String get openLifeTree => '인생 나무 열기';

  @override
  String get openNode => '노드 열기';

  @override
  String get orDivider => '또는';

  @override
  String get pageNotFound => '페이지를 찾을 수 없어요';

  @override
  String get password => '비밀번호';

  @override
  String passwordWithMin(int count) {
    return '비밀번호 ($count자 이상)';
  }

  @override
  String points(int score) {
    return '$score점';
  }

  @override
  String get pointsUnit => '점';

  @override
  String get previous => '이전';

  @override
  String questProgress(int done, int total, int count) {
    return '강좌 $count개, 노드 $total개 중 $done개 클리어.';
  }

  @override
  String get readyToTry => '도전해 볼까요?';

  @override
  String get recorderAsk => '어떤 부분을 잘못 이해했나요?';

  @override
  String get recorderTagline => '실수를 교훈으로 바꿔요';

  @override
  String get removeMainQuest => '메인 퀘스트 삭제';

  @override
  String get removeRule => '규칙 삭제';

  @override
  String get renameUnderCharacter => '이름 변경이나 삭제는 \'내 캐릭터\'에서 할 수 있어요.';

  @override
  String get replayTutorial => '튜토리얼 다시 보기';

  @override
  String resetLinkSent(String email) {
    return '$email(으)로 비밀번호 재설정 링크를 보냈어요.';
  }

  @override
  String get resources => '자료';

  @override
  String get robotAlt => '손바닥 위에 인생 나무를 올린 로봇';

  @override
  String get rulePlaceholder => '예: 첫 심사 전엔 휴대폰 금지';

  @override
  String get rules => '규칙';

  @override
  String get sampleCalculus => '미적분';

  @override
  String get sampleClarity => '명료함';

  @override
  String get sampleDerivatives => '미분';

  @override
  String get sampleInference => '추론';

  @override
  String get sampleIntegrals => '적분';

  @override
  String get sampleLimits => '극한';

  @override
  String get sampleProbability => '확률';

  @override
  String get sampleStatistics => '통계';

  @override
  String get sampleStructure => '구조';

  @override
  String get sampleWriting => '글쓰기';

  @override
  String saveFailed(String error) {
    return '저장하지 못했어요. $error';
  }

  @override
  String get scrollHint => '스크롤';

  @override
  String get search => '검색';

  @override
  String get searchNodesHint => '노드 검색…';

  @override
  String get seeOutline => '개요 보기 →';

  @override
  String get send => '보내기';

  @override
  String get serves => '소속 퀘스트';

  @override
  String get showPassword => '비밀번호 보기';

  @override
  String get sideQuest => '사이드 퀘스트';

  @override
  String get sideQuestCourse => '사이드 퀘스트 · 강좌';

  @override
  String get sideQuestNone => '사이드 퀘스트 (없음)';

  @override
  String get signIn => '로그인';

  @override
  String get signInBlurb => '로그인하고 하던 곳부터 이어서 하세요.';

  @override
  String get signOut => '로그아웃';

  @override
  String get signUpBlurb => '나무, 교훈, 규칙이 모두 계정에 저장돼요.';

  @override
  String get signedInAs => '로그인 계정';

  @override
  String get skip => '건너뛰기';

  @override
  String get sleep => '수면';

  @override
  String get somethingWentWrong => '문제가 생겼어요. 다시 시도해 주세요.';

  @override
  String get somethingWentWrongShort => '문제가 생겼어요.';

  @override
  String sourceLabel(String source) {
    return '출처: $source';
  }

  @override
  String get speakYourAnswer => '말로 답하기';

  @override
  String get stakes => '걸린 것';

  @override
  String get stakesPlaceholder => '아무것도 바뀌지 않으면 어떻게 될까?';

  @override
  String get startAudit => '심사 시작';

  @override
  String get stats => '스탯';

  @override
  String get stopListening => '듣기 멈추기';

  @override
  String get takeItOn => '도전하기';

  @override
  String get today => '오늘';

  @override
  String get tourBallBody => '가운데엔 당신, 주위엔 퀘스트, 그 바깥엔 모든 스킬. 홈 화면에서 구슬을 누르면 나무 전체가 열려요.';

  @override
  String get tourBallKicker => '당신의 수정 구슬';

  @override
  String get tourBallTitle => '인생 나무 전체가 구슬 하나에.';

  @override
  String get tourLessonsBody => '심사에서 떨어지면 어디서 틀렸는지 적어 두세요. 그게 교훈 카드가 되고, 심사관은 다음에 그걸 기억해요.';

  @override
  String get tourLessonsKicker => '교훈';

  @override
  String get tourLessonsTitle => '모든 실수는 교훈이 돼요.';

  @override
  String get tourNext => '다음';

  @override
  String get tourProveBody =>
      '점 하나를 열고 자기 말로 설명해 보세요. 심사관은 당신이 이해했다고 확신할 때까지 계속 물어요. 그러면 그 점이 금색으로 바뀌어요.';

  @override
  String get tourProveKicker => '증명하기';

  @override
  String get tourProveTitle => '설명하세요. 판단은 심사관이 해요.';

  @override
  String get treeStartsWithYou => '나무는 당신에게서 시작돼요.';

  @override
  String get tryAgain => '다시 시도';

  @override
  String get uploadBadFile => '4MB 이하의 PDF, TXT, MD 파일만 올릴 수 있어요.';

  @override
  String get uploadFile => '파일 올리기';

  @override
  String uploadTooMany(int count) {
    return '파일은 최대 $count개까지 첨부할 수 있어요.';
  }

  @override
  String get uploadedCourseMaterial => '업로드한 강의 자료';

  @override
  String get uploading => '올리는 중…';

  @override
  String get verdict => '판정';

  @override
  String get verdictCleared => '통과.';

  @override
  String get verdictNotYet => '아직이에요.';

  @override
  String get viewFrontPage => '첫 화면 보기';

  @override
  String get viewOutline => '개요';

  @override
  String get viewTree => '나무';

  @override
  String get voiceListening => '듣는 중…';

  @override
  String get voiceMode => '음성 모드';

  @override
  String get voiceModeUnavailable => '이 기기에서는 음성 모드를 쓸 수 없어요.';

  @override
  String get voiceSpeaking => '말하는 중…';

  @override
  String get voiceTapToTurnOff => '탭해서 음성 모드 끄기';

  @override
  String get voiceThinking => '생각하는 중…';

  @override
  String get voiceUnavailable => '이 기기에서는 음성 입력을 쓸 수 없어요.';

  @override
  String get welcomeBack => '다시 오신 걸 환영해요';

  @override
  String get whatWasMissing => '빠진 점';

  @override
  String get whatWentWrongHint => '어디서 틀렸나요?…';

  @override
  String get winCondition => '승리 조건';

  @override
  String get winConditionPlaceholder => '이기면 어떤 모습일까?';

  @override
  String get worthSecondLook => '다시 볼 만한 점';

  @override
  String get you => '나';

  @override
  String get onbReadingTitle => '잠깐 살펴볼게요…';

  @override
  String get onbReadingBody => '메인 퀘스트와 맞춰 보는 중이에요.';

  @override
  String get onbPickTitle => '어디서부터 시작할까요?';

  @override
  String get onbPickBody => '하나 고르거나, 더 구체적으로 적어 주세요.';

  @override
  String get deleteCourse => '코스 삭제';

  @override
  String deleteCourseTitle(String course) {
    return '“$course” 코스를 삭제할까요?';
  }

  @override
  String get deleteCourseBody => '인생 나무와 메인 퀘스트에서 빠져요.';

  @override
  String deleteCourseNodes(int count) {
    return '노드 $count개와 그 도전 기록, 교훈 카드도 함께 삭제';
  }

  @override
  String get deleteCourseKeep => '체크하지 않으면 도전 기록과 교훈 카드는 남아요.';

  @override
  String get cancel => '취소';

  @override
  String get delete => '삭제';

  @override
  String get more => '더 보기';
}
