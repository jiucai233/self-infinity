/// The words of the offline fake backend ([FakeApiClient]) in English, Chinese
/// and Korean.
///
/// `FakeScript.of('ko')` picks a language; anything but `zh` / `ko` is English.
/// The English instance holds exactly what the fake always said, so tests that
/// compare against it keep passing. Slugs and ids are not words and stay in
/// `fake_api.dart`.
library;

/// Every line the fake backend writes for the user to read.
abstract class FakeScript {
  const FakeScript();

  /// English (the default), Chinese (Simplified) and Korean.
  static const FakeScript en = _English();
  static const FakeScript zh = _Chinese();
  static const FakeScript ko = _Korean();

  /// The script for a language code (`en`, `zh`, `ko`); anything else is English.
  static FakeScript of(String code) => switch (code) {
    'zh' => zh,
    'ko' => ko,
    _ => en,
  };

  /// What goes between two sentences of a paragraph.
  String get sentenceJoin => ' ';

  /// A title in quotes.
  String quote(String title) => '“$title”';

  // -- courses ----------------------------------------------------------------

  String get mathSource;
  String get newTopic;

  /// Title and description of the 12 math nodes, in order.
  List<(String, String)> get mathNodes;
  List<String> get mathRequires;

  /// The 6 vision nodes.
  List<(String, String)> get visionNodes;

  /// Description of the generic course's root.
  String genericRoot(String rootTitle);

  /// The 9 nodes under the generic root: 3 branches, then 6 leaves.
  List<(String, String)> get genericNodes;
  List<String> get genericRequires;

  String expandMoreTitle(String title);
  String expandMoreBody(String title);
  String expandPartBody(String title, int n);
  String inPractice(String title);

  // -- audits -----------------------------------------------------------------

  String testOutNoParts(String title);
  String testOutFirst(String title, String first);
  String openingTask(String title);
  String openingLeaf(String title);
  String openingBranch(String title, String children);
  String openingRoot(String title);
  String pointsOne(String first);
  String pointsSome(String joined);

  /// Three knowledge points of a leaf (uncut).
  List<String> pointTitles(String title);

  String get genericProbe;
  String onceThought(String misconception);
  String get challenger;
  String get probeFeedback;
  String get passFeedback;
  String get failFeedback;
  String get failNote;
  String get failRight;
  List<String> get failGaps;
  String get failComment;
  String get forcedGap;
  String get forcedComment;
  String get passComment;
  String lessonTitle(String skill);
  String lessonBody(String skill);
  String get linkRelated;
  String get linkContradicts;

  // -- chat -------------------------------------------------------------------

  String buildWorld(String topic);
  String worldReady(String title, int nodes);
  String takingTo(String title);
  String get loggingThat;
  String get pickQuests;
  String todayQuests(String titles);
  String get sumUp;
  String get openingTree;
  String get noted;
  String get askTopic;
  String get noneReply;
  String get noNodeReady;
  String get failBuild;
  String get failLog;
  String get failPlan;
  String get failBrief;
  String get failOther;

  // -- check-in, briefing -----------------------------------------------------

  String sleepPart(String hours);
  String exercisePart(bool yes);
  String mealsPart(String note);
  String focusPart(int n);
  String stressPart(int n);
  String logged(List<String> parts);
  String get nothingToLog;
  String cleared(int mastered, int total);
  String misconceptionSeen(String label, int times, String skills);
  String avgSleep(int days, String hours);

  // -- plan -------------------------------------------------------------------

  String get planRationale;
  String get planFocusHint;
  String get reviewTonight;
  String reviewDays(int days);
  String get reviewHint;
  String get slotMorning;
  String get slotAfternoon;
  String get slotEvening;
  String get slotNight;
  String get lowCondition;
  String get noCheckIn;
  String focusUsedUp(String spent);
  String focusLeft(String left, String spent);
  String duration(int hours, int minutes);

  // -- suggestions, scout, life advice, search --------------------------------

  String get howWasDay;
  String get logMyDay;
  String continueLabel(String title);
  String startLabel(String title);
  String get tellMeWhat;
  String get scoutQuestion;
  String scoutWhy(String goal);
  List<(String, String)> get starterCourses;
  List<(String, String, String)> lifeAdvice({
    String? sleep,
    String? focus,
    required int daysLogged,
  });
  String searchTitle(String query, int i);
  String searchSnippet(String query, int i);
  String get searchReason;
  String explainedQuery(String title);
}

// =============================================================================
// English
// =============================================================================

class _English extends FakeScript {
  const _English();

  @override
  String get mathSource => 'High School Mathematics Curriculum (Ministry of Education)';
  @override
  String get newTopic => 'New Topic';

  @override
  List<(String, String)> get mathNodes => const [
    ('High School Math', 'The backbone of high school math: knowing which tool solves which problem.'),
    ('Algebra', 'Working with numbers and expressions: equations, inequalities, sequences.'),
    ('Functions', 'Describing how two variables relate, with formulas and graphs.'),
    ('Calculus', 'Using limits and rates of change to handle slopes and areas.'),
    ('Quadratic Equations', 'How to solve equations of the form ax²+bx+c=0 and what the roots mean.'),
    ('Discriminant', 'A tool that tells you the kind of roots from the coefficients alone.'),
    ('Roots and Coefficients', 'The link between the sum and product of the roots and the coefficients.'),
    ('Sequences', 'Numbers listed by a rule, including arithmetic and geometric sequences.'),
    ('Linear Functions', 'The slope and intercept of the straight line y=ax+b.'),
    ('Quadratic Functions', 'The vertex, axis and x-intercepts of a parabola.'),
    ('Limits of Sequences', 'The value a sequence approaches as its terms go on forever.'),
    ('Derivatives', 'The instantaneous rate of change at a point, defined as a limit.'),
  ];
  @override
  List<String> get mathRequires => const [
    'The x-intercepts of a quadratic function are the roots of a quadratic equation.',
    'You need the graph of a linear function first.',
    'The derivative is defined as a limit.',
  ];

  @override
  List<(String, String)> get visionNodes => const [
    ('Computer Vision', 'Seeing with cameras and code: features, geometry and recognition.'),
    ('Image Features', 'Points and patches an algorithm can find again: corners and descriptors.'),
    ('Harris Corners', 'Find corners from the structure tensor and explain why edges and flat areas are rejected.'),
    ('SIFT', 'Build scale-invariant keypoints and descriptors and explain how they are matched.'),
    ('Geometric Vision', 'Cameras and 3D: calibration, homography, epipolar geometry, triangulation.'),
    ('Visual Recognition', 'Telling what is in an image: classification, detection, segmentation.'),
  ];

  @override
  String genericRoot(String rootTitle) => 'The starting point that covers all of “$rootTitle”.';
  @override
  List<(String, String)> get genericNodes => const [
    ('Core Concepts', 'The basic ideas that hold this field up.'),
    ('Key Methods', 'The standard ways to solve problems.'),
    ('Applications', 'Applying what you learned to real problems.'),
    ('Core Concepts 1', 'The first core concept.'),
    ('Core Concepts 2', 'The second core concept.'),
    ('Key Methods 1', 'The first key method.'),
    ('Key Methods 2', 'The second key method.'),
    ('Applications 1', 'The first application.'),
    ('Applications 2', 'The second application.'),
  ];
  @override
  List<String> get genericRequires => const [
    'You need the core concepts before using this method.',
    'You need the method before you can apply it.',
  ];

  @override
  String expandMoreTitle(String title) => 'More $title';
  @override
  String expandMoreBody(String title) => 'What $title still lacked.';
  @override
  String expandPartBody(String title, int n) => 'Explain how part $n of $title works and why it holds.';
  @override
  String inPractice(String title) => '$title in Practice';

  @override
  String testOutNoParts(String title) =>
      'So you already know “$title”? Then teach me: what are its main parts, '
      'and how does the most important one work?';
  @override
  String testOutFirst(String title, String first) =>
      'So you already know “$title”? Then teach me, one part at a time. '
      'Start with “$first”: how does it work?';
  @override
  String openingTask(String title) => 'How exactly will you do “$title”?';
  @override
  String openingLeaf(String title) =>
      'I have never learned “$title”. Start small: in a sentence or two, what is it, and what problem does it solve?';
  @override
  String openingBranch(String title, String children) =>
      '“$title” covers $children. '
      'Why do these belong together, and when do you use which?';
  @override
  String openingRoot(String title) =>
      'Which problems call for “$title”, and which don\'t? '
      'How do you decide?';
  @override
  String pointsOne(String first) =>
      'What you taught me last time, I still have. This time teach me only '
      '“$first”, as if I had never heard of it.';
  @override
  String pointsSome(String joined) =>
      'What you taught me last time, I still have. This time teach me '
      '$joined, as if I had never heard of them.';
  @override
  List<String> pointTitles(String title) => ['What $title is', 'Why $title holds', 'Where $title fails'];

  @override
  String get genericProbe =>
      'Pick the most important term in your explanation and tell me what it means and why it matters.';
  @override
  String onceThought(String misconception) =>
      'You once thought “$misconception”. '
      'How is this explanation different?';
  @override
  String get challenger => 'Before I pass this: give one case where this idea does not hold, and explain why.';
  @override
  String get probeFeedback => 'That gives the outline. One part of it is still only named, not explained.';
  @override
  String get passFeedback => 'That is right, and you gave the reason for it.';
  @override
  String get failFeedback => 'The conclusion is there, but the reason behind it is missing.';
  @override
  String get failNote => 'Named it without saying why it holds.';
  @override
  String get failRight => 'The mechanism has to be explained step by step, with what each step is for.';
  @override
  List<String> get failGaps => const [
    'You stated the definition but not why it works.',
    "You didn't cover the exceptions.",
  ];
  @override
  String get failComment => 'The answer stops at the conclusion and lacks reasons.';
  @override
  String get forcedGap => "You couldn't explain the core idea within the turn limit.";
  @override
  String get forcedComment => 'The turns ran out before the explanation was complete.';
  @override
  String get passComment => 'You explained the core idea and why it holds.';
  @override
  String lessonTitle(String skill) => 'Revisit “$skill”';
  @override
  String lessonBody(String skill) => 'When I explain “$skill”, I give the reason before the conclusion.';
  @override
  String get linkRelated => 'Same concept, similar misconception';
  @override
  String get linkContradicts => 'Conflicts with the earlier lesson';

  @override
  String buildWorld(String topic) => "I'll build a world for “$topic”.";
  @override
  String worldReady(String title, int nodes) => 'Your world “$title” is ready — $nodes nodes.';
  @override
  String takingTo(String title) => 'Taking you to “$title”.';
  @override
  String get loggingThat => 'Got it, logging that.';
  @override
  String get pickQuests => "Let me pick today's quests.";
  @override
  String todayQuests(String titles) => "Today's quests: $titles.";
  @override
  String get sumUp => 'Let me sum up where you are.';
  @override
  String get openingTree => 'Opening your life tree.';
  @override
  String get noted => "Noted. It's in your journal.";
  @override
  String get askTopic => 'What topic should I build?';
  @override
  String get noneReply => 'Sure. What would you like to do today?';
  @override
  String get noNodeReady => 'No node is ready yet. Make a world first.';
  @override
  String get failBuild => "I couldn't build that world. Please try again in a moment.";
  @override
  String get failLog => "I couldn't log that. Please try again in a moment.";
  @override
  String get failPlan => "I couldn't pick today's quests. Please try again.";
  @override
  String get failBrief => "I couldn't put your status together. Please try again.";
  @override
  String get failOther => "I couldn't do that right now. Please try again in a moment.";

  @override
  String sleepPart(String hours) => 'sleep $hours h';
  @override
  String exercisePart(bool yes) => 'exercise ${yes ? 'yes' : 'no'}';
  @override
  String mealsPart(String note) => 'meals $note';
  @override
  String focusPart(int n) => 'focus $n/5';
  @override
  String stressPart(int n) => 'stress $n/5';
  @override
  String logged(List<String> parts) => 'Logged: ${parts.join(' · ')}';
  @override
  String get nothingToLog => "I couldn't find anything to log. Tell me about sleep, exercise or meals.";
  @override
  String cleared(int mastered, int total) => "You've cleared $mastered of $total nodes.";
  @override
  String misconceptionSeen(String label, int times, String skills) =>
      'The misconception “$label” showed up $times ${times == 1 ? 'time' : 'times'} in $skills.';
  @override
  String avgSleep(int days, String hours) =>
      'Average sleep over the last ${days == 1 ? 'day' : '$days days'}: $hours h.';

  @override
  String get planRationale => 'Prerequisites checked — you can take this on now.';
  @override
  String get planFocusHint => 'Explain the why before the definition.';
  @override
  String get reviewTonight => 'You learned it today: explain it once more before sleep so it sticks.';
  @override
  String reviewDays(int days) => 'You explained it $days days ago: tell it again before it fades.';
  @override
  String get reviewHint => 'Say it from memory first, then check what you left out.';
  @override
  String get slotMorning => 'Morning: judgement first, new nodes and challenges; review waits for the evening.';
  @override
  String get slotAfternoon => 'Afternoon: new nodes, with some review.';
  @override
  String get slotEvening => 'Evening: mostly review. Explaining again what you learned helps sleep keep it.';
  @override
  String get slotNight => "It's late: one short review at most, then sleep. Sleep does the consolidating.";
  @override
  String get lowCondition =>
      "Your recent check-ins show a low condition, so today's load is halved: small nodes and review only.";
  @override
  String get noCheckIn => 'No check-in yet, so I planned for three hours.';
  @override
  String focusUsedUp(String spent) =>
      "Today's focus is used up ($spent). The rest of the day is for rest and sleep.";
  @override
  String focusLeft(String left, String spent) => 'About $left of focus left today ($spent done).';
  @override
  String duration(int hours, int minutes) =>
      hours > 0 && minutes > 0 ? '$hours h $minutes min' : (hours > 0 ? '$hours h' : '$minutes min');

  @override
  String get howWasDay => 'How was your day?';
  @override
  String get logMyDay => 'Let me log my day';
  @override
  String continueLabel(String title) => 'Continue “$title”';
  @override
  String startLabel(String title) => 'Start with “$title”';
  @override
  String get tellMeWhat => 'Tell me what you want to learn';
  @override
  String get scoutQuestion => 'Here are a few places to start. Pick one:';
  @override
  String scoutWhy(String goal) => 'It is what “$goal” needs first.';
  @override
  List<(String, String)> get starterCourses => const [
    ('Python programming basics', 'A tool almost every other course leans on.'),
    ('Linear algebra', 'The language of data, graphics and machine learning.'),
    ('Clear technical writing', 'Explaining things well is how you prove them here.'),
  ];
  @override
  List<(String, String, String)> lifeAdvice({String? sleep, String? focus, required int daysLogged}) => [
    if (sleep != null)
      (
        'Protect your sleep',
        'Pick a fixed time to stop screens this week and keep it five nights.',
        'slept $sleep h on average',
      ),
    if (focus != null)
      (
        'Audit when you focus best',
        'Put this week\'s audits in the part of the day you feel sharpest.',
        'focus $focus of 5 on average',
      ),
    (
      'Log a few more days',
      'Check in every day this week, even briefly, so your own patterns can show up.',
      '$daysLogged of 14 days logged',
    ),
  ];
  @override
  String searchTitle(String query, int i) => '“$query” — resource $i';
  @override
  String searchSnippet(String query, int i) => 'Mock search result $i for “$query”. Offline demo text.';
  @override
  String get searchReason => 'Covers this gap directly.';
  @override
  String explainedQuery(String title) => '$title explained';
}

// =============================================================================
// Korean
// =============================================================================

class _Korean extends FakeScript {
  const _Korean();

  @override
  String get mathSource => '고등학교 수학 교육과정 (교육부)';
  @override
  String get newTopic => '새 주제';

  @override
  List<(String, String)> get mathNodes => const [
    ('고등학교 수학', '고등학교 수학의 뼈대예요. 어떤 문제에 어떤 도구를 쓸지 아는 것.'),
    ('대수', '수와 식을 다뤄요. 방정식, 부등식, 수열.'),
    ('함수', '두 변수의 관계를 식과 그래프로 나타내요.'),
    ('미적분', '극한과 변화율로 기울기와 넓이를 다뤄요.'),
    ('이차방정식', 'ax²+bx+c=0 꼴의 방정식을 푸는 방법과 근의 의미.'),
    ('판별식', '계수만으로 근의 종류를 알려 주는 도구.'),
    ('근과 계수의 관계', '두 근의 합·곱과 계수 사이의 관계.'),
    ('수열', '규칙에 따라 늘어놓은 수. 등차수열과 등비수열을 포함해요.'),
    ('일차함수', '직선 y=ax+b의 기울기와 절편.'),
    ('이차함수', '포물선의 꼭짓점, 축, x절편.'),
    ('수열의 극한', '항이 끝없이 이어질 때 수열이 가까워지는 값.'),
    ('도함수', '한 점에서의 순간 변화율. 극한으로 정의해요.'),
  ];
  @override
  List<String> get mathRequires => const [
    '이차함수의 x절편은 이차방정식의 근이에요.',
    '먼저 일차함수의 그래프를 알아야 해요.',
    '도함수는 극한으로 정의돼요.',
  ];

  @override
  List<(String, String)> get visionNodes => const [
    ('컴퓨터 비전', '카메라와 코드로 보기: 특징, 기하, 인식.'),
    ('이미지 특징', '알고리즘이 다시 찾을 수 있는 점과 패치: 코너와 기술자.'),
    ('해리스 코너', '구조 텐서로 코너를 찾고, 가장자리와 평평한 영역이 왜 제외되는지 설명해요.'),
    ('SIFT', '스케일에 변하지 않는 키포인트와 기술자를 만들고, 어떻게 매칭되는지 설명해요.'),
    ('기하 비전', '카메라와 3D: 캘리브레이션, 호모그래피, 에피폴라 기하, 삼각측량.'),
    ('시각 인식', '이미지 속에 무엇이 있는지 알아내기: 분류, 검출, 분할.'),
  ];

  @override
  String genericRoot(String rootTitle) => '“$rootTitle” 전체를 아우르는 출발점.';
  @override
  List<(String, String)> get genericNodes => const [
    ('핵심 개념', '이 분야를 떠받치는 기본 아이디어.'),
    ('핵심 방법', '문제를 푸는 표준적인 방법.'),
    ('활용', '배운 것을 실제 문제에 적용하기.'),
    ('핵심 개념 1', '첫 번째 핵심 개념.'),
    ('핵심 개념 2', '두 번째 핵심 개념.'),
    ('핵심 방법 1', '첫 번째 핵심 방법.'),
    ('핵심 방법 2', '두 번째 핵심 방법.'),
    ('활용 1', '첫 번째 활용.'),
    ('활용 2', '두 번째 활용.'),
  ];
  @override
  List<String> get genericRequires => const [
    '이 방법을 쓰기 전에 핵심 개념을 알아야 해요.',
    '활용하려면 먼저 그 방법을 알아야 해요.',
  ];

  @override
  String expandMoreTitle(String title) => '$title 보충';
  @override
  String expandMoreBody(String title) => '$title에 아직 부족했던 부분.';
  @override
  String expandPartBody(String title, int n) => '$title의 $n번째 부분이 어떻게 작동하는지, 왜 성립하는지 설명해 보세요.';
  @override
  String inPractice(String title) => '$title 실전';

  @override
  String testOutNoParts(String title) =>
      '“$title”, 이미 알고 계신가요? 그럼 저를 가르쳐 주세요. 주요 부분은 무엇이고, '
      '가장 중요한 부분은 어떻게 작동하나요?';
  @override
  String testOutFirst(String title, String first) =>
      '“$title”, 이미 알고 계신가요? 그럼 한 부분씩 가르쳐 주세요. '
      '“$first”부터 시작해요. 어떻게 작동하나요?';
  @override
  String openingTask(String title) => '“$title”, 구체적으로 어떻게 할 건가요?';
  @override
  String openingLeaf(String title) =>
      '“$title”, 저는 한 번도 배운 적이 없어요. 작게 시작해 봐요. 한두 문장으로, 그게 무엇이고 어떤 문제를 푸나요?';
  @override
  String openingBranch(String title, String children) =>
      '“$title”에는 이런 것들이 들어 있어요: $children. '
      '이것들은 왜 한데 묶여 있고, 언제 무엇을 쓰나요?';
  @override
  String openingRoot(String title) =>
      '“$title”, 어떤 문제에는 필요하고 어떤 문제에는 필요 없나요? '
      '어떻게 판단하나요?';
  @override
  String pointsOne(String first) =>
      '지난번에 가르쳐 주신 건 아직 기억해요. 이번에는 “$first”만, '
      '처음 들어 보는 사람에게 가르치듯 알려 주세요.';
  @override
  String pointsSome(String joined) =>
      '지난번에 가르쳐 주신 건 아직 기억해요. 이번에는 처음 들어 보는 사람에게 가르치듯 '
      '이 부분들을 알려 주세요: $joined.';
  @override
  List<String> pointTitles(String title) => ['$title: 무엇인가', '$title: 왜 성립하는가', '$title: 어디서 무너지는가'];

  @override
  String get genericProbe => '설명에서 가장 중요한 용어 하나를 골라, 그게 무슨 뜻이고 왜 중요한지 말해 주세요.';
  @override
  String onceThought(String misconception) => '예전에 “$misconception”라고 생각하셨죠. 이번 설명은 그때와 어떻게 다른가요?';
  @override
  String get challenger => '통과시키기 전에 하나만 더요. 이 생각이 성립하지 않는 경우를 하나 들고, 왜 그런지 설명해 주세요.';
  @override
  String get probeFeedback => '큰 줄기는 나왔어요. 다만 한 부분은 이름만 나왔고 설명은 아직이에요.';
  @override
  String get passFeedback => '맞아요. 이유까지 잘 설명해 주셨어요.';
  @override
  String get failFeedback => '결론은 있는데, 그 뒤의 이유가 빠져 있어요.';
  @override
  String get failNote => '이유 없이 이름만 말했어요.';
  @override
  String get failRight => '원리는 단계별로, 각 단계가 무엇을 위한 것인지와 함께 설명해야 해요.';
  @override
  List<String> get failGaps => const [
    '정의는 말했지만 왜 성립하는지는 말하지 않았어요.',
    '예외는 다루지 않았어요.',
  ];
  @override
  String get failComment => '답이 결론에서 멈췄고, 이유가 부족해요.';
  @override
  String get forcedGap => '턴 제한 안에 핵심 아이디어를 설명하지 못했어요.';
  @override
  String get forcedComment => '설명을 마치기 전에 턴이 다 끝났어요.';
  @override
  String get passComment => '핵심 아이디어와 그것이 성립하는 이유를 설명했어요.';
  @override
  String lessonTitle(String skill) => '“$skill” 다시 보기';
  @override
  String lessonBody(String skill) => '“$skill” 설명할 때는 결론보다 이유를 먼저 말하기.';
  @override
  String get linkRelated => '같은 개념, 비슷한 오해';
  @override
  String get linkContradicts => '이전 교훈과 충돌해요';

  @override
  String buildWorld(String topic) => '“$topic” 세계를 만들게요.';
  @override
  String worldReady(String title, int nodes) => '“$title” 세계가 준비됐어요 — 노드 $nodes개.';
  @override
  String takingTo(String title) => '“$title” 노드로 갈게요.';
  @override
  String get loggingThat => '알겠어요, 기록할게요.';
  @override
  String get pickQuests => '오늘의 퀘스트를 골라 볼게요.';
  @override
  String todayQuests(String titles) => '오늘의 퀘스트: $titles.';
  @override
  String get sumUp => '지금 어디쯤인지 정리해 볼게요.';
  @override
  String get openingTree => '인생 나무를 열게요.';
  @override
  String get noted => '기록했어요. 일기에 들어 있어요.';
  @override
  String get askTopic => '어떤 주제로 세계를 만들까요?';
  @override
  String get noneReply => '좋아요. 오늘은 뭘 하고 싶으세요?';
  @override
  String get noNodeReady => '아직 준비된 노드가 없어요. 먼저 세계를 만들어 보세요.';
  @override
  String get failBuild => '세계를 만들지 못했어요. 잠시 후 다시 시도해 주세요.';
  @override
  String get failLog => '기록하지 못했어요. 잠시 후 다시 시도해 주세요.';
  @override
  String get failPlan => '오늘의 퀘스트를 고르지 못했어요. 다시 시도해 주세요.';
  @override
  String get failBrief => '현황을 정리하지 못했어요. 다시 시도해 주세요.';
  @override
  String get failOther => '지금은 할 수 없어요. 잠시 후 다시 시도해 주세요.';

  @override
  String sleepPart(String hours) => '수면 $hours시간';
  @override
  String exercisePart(bool yes) => '운동 ${yes ? '함' : '안 함'}';
  @override
  String mealsPart(String note) => '식사 $note';
  @override
  String focusPart(int n) => '집중 $n/5';
  @override
  String stressPart(int n) => '스트레스 $n/5';
  @override
  String logged(List<String> parts) => '기록했어요: ${parts.join(' · ')}';
  @override
  String get nothingToLog => '기록할 내용을 찾지 못했어요. 수면, 운동, 식사에 대해 말해 주세요.';
  @override
  String cleared(int mastered, int total) => '노드 $total개 중 $mastered개를 클리어했어요.';
  @override
  String misconceptionSeen(String label, int times, String skills) => '오해 “$label”: $skills에서 $times번 나타났어요.';
  @override
  String avgSleep(int days, String hours) => '최근 ${days == 1 ? '하루' : '$days일'} 평균 수면: $hours시간.';

  @override
  String get planRationale => '선행 조건을 확인했어요. 지금 도전할 수 있어요.';
  @override
  String get planFocusHint => '정의보다 이유를 먼저 설명해 보세요.';
  @override
  String get reviewTonight => '오늘 배웠어요. 자기 전에 한 번 더 설명하면 기억에 남아요.';
  @override
  String reviewDays(int days) => '$days일 전에 설명했어요. 잊히기 전에 다시 말해 보세요.';
  @override
  String get reviewHint => '먼저 기억만으로 말해 본 뒤, 빠뜨린 것을 확인하세요.';
  @override
  String get slotMorning => '아침: 판단이 먼저예요. 새 노드와 도전을 하고, 복습은 저녁에 해요.';
  @override
  String get slotAfternoon => '오후: 새 노드를 하고, 복습도 조금 해요.';
  @override
  String get slotEvening => '저녁: 대부분 복습이에요. 배운 걸 다시 설명하면 잠이 기억을 붙들어 줘요.';
  @override
  String get slotNight => '늦었어요. 짧은 복습 하나만 하고 자요. 기억은 잠이 굳혀 줘요.';
  @override
  String get lowCondition => '최근 체크인에서 컨디션이 낮아 보여서 오늘 분량을 절반으로 줄였어요. 작은 노드와 복습만 해요.';
  @override
  String get noCheckIn => '아직 체크인이 없어서 세 시간 기준으로 짰어요.';
  @override
  String focusUsedUp(String spent) => '오늘 집중할 수 있는 시간을 다 썼어요($spent). 남은 시간은 쉬고 자요.';
  @override
  String focusLeft(String left, String spent) => '오늘 집중할 수 있는 시간이 약 $left 남았어요($spent 했어요).';
  @override
  String duration(int hours, int minutes) =>
      hours > 0 && minutes > 0 ? '$hours시간 $minutes분' : (hours > 0 ? '$hours시간' : '$minutes분');

  @override
  String get howWasDay => '오늘 하루는 어땠어요?';
  @override
  String get logMyDay => '오늘 하루 기록할래요';
  @override
  String continueLabel(String title) => '“$title” 이어서 하기';
  @override
  String startLabel(String title) => '“$title”부터 시작하기';
  @override
  String get tellMeWhat => '배우고 싶은 걸 알려 주세요';
  @override
  String get scoutQuestion => '시작할 만한 곳을 몇 가지 골랐어요. 하나를 골라 주세요:';
  @override
  String scoutWhy(String goal) => '“$goal”에 가장 먼저 필요한 내용이에요.';
  @override
  List<(String, String)> get starterCourses => const [
    ('파이썬 프로그래밍 기초', '거의 모든 다른 과정이 기대는 도구예요.'),
    ('선형대수', '데이터, 그래픽, 머신러닝의 언어예요.'),
    ('명확한 기술 글쓰기', '잘 설명하는 것이 여기서 이해를 증명하는 방법이에요.'),
  ];
  @override
  List<(String, String, String)> lifeAdvice({String? sleep, String? focus, required int daysLogged}) => [
    if (sleep != null)
      ('수면 지키기', '이번 주는 화면을 끄는 시간을 정해 두고 다섯 밤 동안 지켜 보세요.', '평균 $sleep시간 잤어요'),
    if (focus != null)
      ('집중이 잘될 때 심사받기', '이번 주 심사는 가장 머리가 맑다고 느끼는 시간대에 잡아 보세요.', '평균 집중 $focus/5'),
    ('며칠 더 기록하기', '이번 주에는 짧게라도 매일 체크인해서 나만의 패턴이 보이게 해요.', '14일 중 $daysLogged일 기록'),
  ];
  @override
  String searchTitle(String query, int i) => '“$query” — 자료 $i';
  @override
  String searchSnippet(String query, int i) => '“$query”에 대한 모의 검색 결과 $i. 오프라인 데모 텍스트.';
  @override
  String get searchReason => '이 빈틈을 바로 다뤄요.';
  @override
  String explainedQuery(String title) => '$title 설명';
}

// =============================================================================
// Chinese (Simplified)
// =============================================================================

class _Chinese extends FakeScript {
  const _Chinese();

  @override
  String get sentenceJoin => '';
  @override
  String quote(String title) => '「$title」';

  @override
  String get mathSource => '高中数学课程标准（教育部）';
  @override
  String get newTopic => '新主题';

  @override
  List<(String, String)> get mathNodes => const [
    ('高中数学', '高中数学的主干：知道什么问题该用什么工具。'),
    ('代数', '处理数与式：方程、不等式、数列。'),
    ('函数', '用公式和图像描述两个变量之间的关系。'),
    ('微积分', '用极限和变化率处理斜率与面积。'),
    ('一元二次方程', '形如 ax²+bx+c=0 的方程怎么解，以及根的含义。'),
    ('判别式', '只看系数就能判断根的类型的工具。'),
    ('根与系数的关系', '两根之和、两根之积与系数之间的联系。'),
    ('数列', '按规则排列的一列数，包括等差数列和等比数列。'),
    ('一次函数', '直线 y=ax+b 的斜率和截距。'),
    ('二次函数', '抛物线的顶点、对称轴和与 x 轴的交点。'),
    ('数列的极限', '数列的项无限延续时所趋近的值。'),
    ('导数', '某一点的瞬时变化率，用极限来定义。'),
  ];
  @override
  List<String> get mathRequires => const [
    '二次函数与 x 轴的交点，就是一元二次方程的根。',
    '需要先掌握一次函数的图像。',
    '导数是用极限定义的。',
  ];

  @override
  List<(String, String)> get visionNodes => const [
    ('计算机视觉', '用相机和代码来“看”：特征、几何与识别。'),
    ('图像特征', '算法能再次找到的点和图像块：角点与描述子。'),
    ('Harris 角点', '用结构张量找出角点，并解释为什么边缘和平坦区域会被排除。'),
    ('SIFT', '构建尺度不变的关键点和描述子，并解释它们如何匹配。'),
    ('几何视觉', '相机与三维：标定、单应性、对极几何、三角测量。'),
    ('视觉识别', '判断图像里有什么：分类、检测、分割。'),
  ];

  @override
  String genericRoot(String rootTitle) => '涵盖「$rootTitle」全部内容的起点。';
  @override
  List<(String, String)> get genericNodes => const [
    ('核心概念', '支撑这个领域的基本思想。'),
    ('关键方法', '解决问题的标准方法。'),
    ('实际应用', '把学到的东西用到真实问题上。'),
    ('核心概念 1', '第一个核心概念。'),
    ('核心概念 2', '第二个核心概念。'),
    ('关键方法 1', '第一个关键方法。'),
    ('关键方法 2', '第二个关键方法。'),
    ('实际应用 1', '第一个应用。'),
    ('实际应用 2', '第二个应用。'),
  ];
  @override
  List<String> get genericRequires => const [
    '使用这个方法之前，需要先掌握核心概念。',
    '要先掌握这个方法，才能应用它。',
  ];

  @override
  String expandMoreTitle(String title) => '$title 补充';
  @override
  String expandMoreBody(String title) => '$title 还欠缺的部分。';
  @override
  String expandPartBody(String title, int n) => '解释 $title 的第 $n 部分如何运作、为什么成立。';
  @override
  String inPractice(String title) => '$title 实践';

  @override
  String testOutNoParts(String title) => '你已经懂「$title」了？那就来教我：它有哪些主要部分，最重要的那一部分是怎么运作的？';
  @override
  String testOutFirst(String title, String first) => '你已经懂「$title」了？那就一部分一部分地教我。先从「$first」开始：它是怎么运作的？';
  @override
  String openingTask(String title) => '你具体打算怎么做「$title」？';
  @override
  String openingLeaf(String title) => '我从没学过「$title」。从小处开始：用一两句话说说，它是什么，解决什么问题？';
  @override
  String openingBranch(String title, String children) => '「$title」包含$children。为什么这些放在一起，什么时候用哪一个？';
  @override
  String openingRoot(String title) => '哪些问题需要「$title」，哪些不需要？你怎么判断？';
  @override
  String pointsOne(String first) => '上次你教我的，我还记得。这次请只教我「$first」，就当我从没听过。';
  @override
  String pointsSome(String joined) => '上次你教我的，我还记得。这次请教我这几部分：$joined，就当我从没听过。';
  @override
  List<String> pointTitles(String title) => ['$title 是什么', '$title 为什么成立', '$title 在哪里失效'];

  @override
  String get genericProbe => '请从你的解释中选出最重要的一个术语，说说它是什么意思、为什么重要。';
  @override
  String onceThought(String misconception) => '你曾经认为「$misconception」。这次的解释有什么不同？';
  @override
  String get challenger => '通过之前再问一个：请举一个这个想法不成立的例子，并解释原因。';
  @override
  String get probeFeedback => '大致框架有了，但有一部分只提到了名字，还没有解释。';
  @override
  String get passFeedback => '没错，而且你把原因也讲清楚了。';
  @override
  String get failFeedback => '结论有了，但背后的原因还缺少。';
  @override
  String get failNote => '只说了名称，没有说明为什么成立。';
  @override
  String get failRight => '原理需要一步一步讲清楚，并说明每一步的作用。';
  @override
  List<String> get failGaps => const [
    '你说出了定义，但没有说明它为什么成立。',
    '没有涉及例外情况。',
  ];
  @override
  String get failComment => '回答停在结论上，缺少理由。';
  @override
  String get forcedGap => '在轮数限制内没能讲清核心思想。';
  @override
  String get forcedComment => '解释还没完成，轮数就用完了。';
  @override
  String get passComment => '你讲清了核心思想以及它成立的原因。';
  @override
  String lessonTitle(String skill) => '回顾「$skill」';
  @override
  String lessonBody(String skill) => '解释「$skill」时，先讲理由，再讲结论。';
  @override
  String get linkRelated => '同一概念，相似的误解';
  @override
  String get linkContradicts => '与之前的教训相冲突';

  @override
  String buildWorld(String topic) => '我来为「$topic」建一个世界。';
  @override
  String worldReady(String title, int nodes) => '你的「$title」世界已就绪，共 $nodes 个节点。';
  @override
  String takingTo(String title) => '带你去「$title」。';
  @override
  String get loggingThat => '好的，我来记录。';
  @override
  String get pickQuests => '我来挑今天的任务。';
  @override
  String todayQuests(String titles) => '今天的任务：$titles。';
  @override
  String get sumUp => '我来总结一下你现在的进度。';
  @override
  String get openingTree => '打开你的人生树。';
  @override
  String get noted => '记下了，已放进你的日记。';
  @override
  String get askTopic => '要为哪个主题建世界？';
  @override
  String get noneReply => '好的。今天想做什么？';
  @override
  String get noNodeReady => '还没有可用的节点。先建一个世界吧。';
  @override
  String get failBuild => '没能建好这个世界，请稍后再试。';
  @override
  String get failLog => '没能记录，请稍后再试。';
  @override
  String get failPlan => '没能挑出今天的任务，请再试一次。';
  @override
  String get failBrief => '没能整理出你的状态，请再试一次。';
  @override
  String get failOther => '现在做不到，请稍后再试。';

  @override
  String sleepPart(String hours) => '睡眠 $hours 小时';
  @override
  String exercisePart(bool yes) => '运动 ${yes ? '有' : '无'}';
  @override
  String mealsPart(String note) => '饮食 $note';
  @override
  String focusPart(int n) => '专注 $n/5';
  @override
  String stressPart(int n) => '压力 $n/5';
  @override
  String logged(List<String> parts) => '已记录：${parts.join(' · ')}';
  @override
  String get nothingToLog => '没有找到可记录的内容。说说睡眠、运动或饮食吧。';
  @override
  String cleared(int mastered, int total) => '你已通关 $mastered/$total 个节点。';
  @override
  String misconceptionSeen(String label, int times, String skills) => '误解「$label」在$skills中出现了 $times 次。';
  @override
  String avgSleep(int days, String hours) => '最近${days == 1 ? '一天' : '$days 天'}的平均睡眠：$hours 小时。';

  @override
  String get planRationale => '前置条件已满足，现在可以开始了。';
  @override
  String get planFocusHint => '先讲为什么，再讲定义。';
  @override
  String get reviewTonight => '你今天学过它：睡前再讲一遍，记得更牢。';
  @override
  String reviewDays(int days) => '你在 $days 天前讲过它：趁还没忘，再讲一遍。';
  @override
  String get reviewHint => '先凭记忆讲一遍，再检查漏了什么。';
  @override
  String get slotMorning => '上午：先做判断，学新节点、做挑战；复习留到晚上。';
  @override
  String get slotAfternoon => '下午：学新节点，再加一点复习。';
  @override
  String get slotEvening => '晚上：以复习为主。把学过的再讲一遍，有助于睡眠巩固记忆。';
  @override
  String get slotNight => '很晚了：最多做一次简短复习，然后睡觉。巩固交给睡眠。';
  @override
  String get lowCondition => '最近的打卡显示状态不佳，所以今天的量减半：只做小节点和复习。';
  @override
  String get noCheckIn => '还没有打卡，所以按三个小时来安排。';
  @override
  String focusUsedUp(String spent) => '今天的专注时间已用完（$spent）。剩下的时间留给休息和睡眠。';
  @override
  String focusLeft(String left, String spent) => '今天还剩约 $left 的专注时间（已完成 $spent）。';
  @override
  String duration(int hours, int minutes) =>
      hours > 0 && minutes > 0 ? '$hours 小时 $minutes 分钟' : (hours > 0 ? '$hours 小时' : '$minutes 分钟');

  @override
  String get howWasDay => '今天过得怎么样？';
  @override
  String get logMyDay => '记录一下今天';
  @override
  String continueLabel(String title) => '继续「$title」';
  @override
  String startLabel(String title) => '从「$title」开始';
  @override
  String get tellMeWhat => '告诉我你想学什么';
  @override
  String get scoutQuestion => '这里有几个可以开始的方向，选一个吧：';
  @override
  String scoutWhy(String goal) => '这是「$goal」最先需要的。';
  @override
  List<(String, String)> get starterCourses => const [
    ('Python 编程基础', '几乎所有其他课程都要用到的工具。'),
    ('线性代数', '数据、图形和机器学习的语言。'),
    ('清晰的技术写作', '把事情讲清楚，就是在这里证明你懂了的方式。'),
  ];
  @override
  List<(String, String, String)> lifeAdvice({String? sleep, String? focus, required int daysLogged}) => [
    if (sleep != null) ('守护睡眠', '这周定一个固定的关屏时间，坚持五个晚上。', '平均睡 $sleep 小时'),
    if (focus != null) ('在专注力最好时接受审核', '把这周的审核安排在你感觉最清醒的时段。', '专注度平均 $focus/5'),
    ('再多记录几天', '这周每天打卡，哪怕只写一点，这样你自己的规律才会显现。', '14 天中记录了 $daysLogged 天'),
  ];
  @override
  String searchTitle(String query, int i) => '「$query」— 资料 $i';
  @override
  String searchSnippet(String query, int i) => '「$query」的模拟搜索结果 $i。离线演示文本。';
  @override
  String get searchReason => '直接针对这个薄弱点。';
  @override
  String explainedQuery(String title) => '$title 讲解';
}
