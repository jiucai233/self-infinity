// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get about => '简介';

  @override
  String aboutNodeMessage(String title, String text) {
    return '关于「$title」：$text';
  }

  @override
  String get account => '账户';

  @override
  String get addMainQuest => '添加主线任务';

  @override
  String get addRule => '添加规则';

  @override
  String get agentAuditor => '审核官';

  @override
  String get agentChallenger => '质疑者';

  @override
  String get agentCheckIn => '打卡';

  @override
  String get agentClarifier => '澄清者';

  @override
  String get agentGuide => '向导';

  @override
  String get agentLinker => '连线者';

  @override
  String get agentMaterialFinder => '资料搜寻者';

  @override
  String get agentNarrator => '讲述者';

  @override
  String get agentPlanner => '规划者';

  @override
  String get agentRecommender => '推荐者';

  @override
  String get agentRecorder => '记录者';

  @override
  String get agentSyllabusFinder => '大纲搜寻者';

  @override
  String get answerHint => '你的回答…';

  @override
  String get askAboutNodeHint => '问问这个节点…';

  @override
  String get askTodaysQuests => '我今天该做什么？';

  @override
  String get attachCourse => '关联一门课程';

  @override
  String get attempts => '尝试';

  @override
  String get auditFailed => '未通过';

  @override
  String get auditHistory => '审核记录';

  @override
  String get auditInProgress => '进行中';

  @override
  String get auditPassed => '已通过';

  @override
  String get auditorTagline => '像新手一样提问，像专家一样评判';

  @override
  String get authAlreadyRegistered => '这个邮箱已经注册过了，直接登录吧。';

  @override
  String get authConfirmEmailFirst => '请先确认邮箱——去收件箱看看。';

  @override
  String get authEnterPassword => '请输入密码。';

  @override
  String get authInvalidEmail => '请输入有效的邮箱地址。';

  @override
  String get authOffline => '连不上服务器，请检查网络。';

  @override
  String authPasswordTooShort(int count) {
    return '密码至少需要 $count 个字符。';
  }

  @override
  String get authRateLimited => '尝试次数太多，请等一分钟再试。';

  @override
  String get authWrongCredentials => '邮箱或密码不对。';

  @override
  String get back => '返回';

  @override
  String get backToNode => '返回节点';

  @override
  String get backToSignIn => '返回登录';

  @override
  String get best => '最高分';

  @override
  String get boss => 'Boss';

  @override
  String get bossCleared => '击败 Boss！';

  @override
  String get callingAuditor => '正在请审核官…';

  @override
  String get chapterGrowBody => '课程挂在你为今年设定的主线任务下面。你证明的每一样东西，都会点亮这个球里的一个点：这就是你的人生树。';

  @override
  String get chapterGrowKicker => '04 · 成长';

  @override
  String get chapterGrowTitle => '你的整个人生，一棵树。';

  @override
  String get chapterLearnBody => '告诉向导你想学什么。它会找来一份真实的课程大纲，把它变成一棵等你逐个证明的知识树。';

  @override
  String get chapterLearnKicker => '01 · 学';

  @override
  String get chapterLearnTitle => '想学什么都行，拿到真实的课程大纲。';

  @override
  String get chapterProveBody => '没有选择题。审核官像新手一样提问、像专家一样评判，质疑者还会复核每一次通过。只有真的懂了，节点才会变成金色。';

  @override
  String get chapterProveKicker => '02 · 证明';

  @override
  String get chapterRememberBody => '答错了就写下原因。它会变成一张教训卡，审核官下次会专门提起，同一个误解没法溜过去两次。';

  @override
  String get chapterRememberKicker => '03 · 记住';

  @override
  String get characterSheet => '角色卡';

  @override
  String get chatTitle => '对话';

  @override
  String get checkInbox => '去收件箱看看';

  @override
  String get chooseMainQuest => '选择主线任务';

  @override
  String get cleared => '通关！';

  @override
  String clearedBar(int mastered, int total) {
    return '已通关 $mastered/$total';
  }

  @override
  String clearedWithScore(int score) {
    return '通关！$score 分';
  }

  @override
  String get close => '关闭';

  @override
  String get collapse => '收起';

  @override
  String conditionBar(String state) {
    return '状态：$state';
  }

  @override
  String get conditionGood => '良好';

  @override
  String get conditionLow => '偏低';

  @override
  String get conditionNoRecord => '无记录';

  @override
  String confirmLinkSent(String email) {
    return '我们给 $email 发了一封邮件。打开里面的链接确认邮箱，然后回这里登录。';
  }

  @override
  String get continueLabel => '继续';

  @override
  String get continueWithGoogle => '使用 Google 继续';

  @override
  String get course => '课程';

  @override
  String get courses => '课程';

  @override
  String get createAccount => '创建账户';

  @override
  String get createAnAccount => '创建账户';

  @override
  String get createYourAccount => '创建你的账户';

  @override
  String get crystalBall => '水晶球';

  @override
  String get dailyQuests => '每日任务';

  @override
  String get dotCleared => '已通关';

  @override
  String get dotLocked => '未解锁';

  @override
  String get dotReady => '可挑战';

  @override
  String get dragToTurn => '拖动旋转 · 点选一个点';

  @override
  String get editUnderCharacter => '可以在「我的角色」里编辑。';

  @override
  String get email => '邮箱';

  @override
  String get enterApp => '进入 Self-Infinity';

  @override
  String get enterEmailFirst => '请先在上面填写邮箱。';

  @override
  String get errAiFailure => '我们这边出了点问题，请再试一次。';

  @override
  String get errAuditClosed => '这次审核已经结束了。';

  @override
  String get errBadRequest => '现在还不能这样做。';

  @override
  String get errFileUnreadable => '这个文件里读不出文字。';

  @override
  String get errInvalidInput => '请检查一下你输入的内容。';

  @override
  String get errLessonAlreadyMade => '教训卡已经生成过了。';

  @override
  String get errLessonOnlyAfterFail => '只有审核没通过时才能生成教训卡。';

  @override
  String get errMaxMainQuests => '主线任务最多只能有 3 个。';

  @override
  String get errNetwork => '连不上服务器，请检查网络。';

  @override
  String get errNoNodeReady => '还没有可挑战的节点。先建一个世界吧。';

  @override
  String get errNodeLocked => '这个节点还没解锁。先通关它的上一级。';

  @override
  String get errNotFound => '找不到这个内容。';

  @override
  String get errPickGap => '选一个漏洞或误解再去搜索。';

  @override
  String get errSignedOut => '登录已过期，请重新登录。';

  @override
  String get expand => '展开';

  @override
  String get explainHint => '用你自己的话讲一讲…';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get getStarted => '开始';

  @override
  String get getTodaysQuests => '领取今天的任务 →';

  @override
  String get goHome => '回到首页';

  @override
  String get googleFailed => '无法打开 Google 登录，请再试一次。';

  @override
  String greetingContinue(String course) {
    return '继续学「$course」吗？';
  }

  @override
  String get greetingNew => '今天学点什么？';

  @override
  String get haveAccount => '已经有账户了？';

  @override
  String get haveAnAccountButton => '我已有账户';

  @override
  String get heroHeadline => '证明你真的懂了，\n看着你的树长大。';

  @override
  String get heroLead => '一个不让你装懂的 AI。只有用自己的话讲明白学到的东西，你才能升级。';

  @override
  String get heroTagline => '一个靠讲明白来取胜的学习游戏';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get hintContinue => '点一下水晶球，打开你的人生树。';

  @override
  String get hintNew => '告诉向导你想学什么。';

  @override
  String hoursShort(String hours) {
    return '$hours 小时';
  }

  @override
  String get identityPlaceholder => '我是那种……的人';

  @override
  String get identityStem => '我是那种';

  @override
  String get journal => '日记';

  @override
  String get language => '语言';

  @override
  String get lessonCard => '教训卡';

  @override
  String get lessonCardCreated => '教训卡已生成。';

  @override
  String get lessonCards => '教训卡';

  @override
  String get lessons => '教训';

  @override
  String levelBar(int level, int progress) {
    return 'Lv $level · $progress/5';
  }

  @override
  String get lifeTree => '人生树';

  @override
  String get linkOpenFailed => '打不开这个链接。';

  @override
  String get loading => '加载中…';

  @override
  String get localModeNoAccount => '本地模式（无账户）';

  @override
  String lockedClearNamed(String title) {
    return '还没解锁。先通关「$title」。';
  }

  @override
  String get lockedClearParent => '还没解锁。先通关上一级节点。';

  @override
  String get mainQuest => '主线任务';

  @override
  String get mainQuestPlaceholder => '例如：给陌生人讲懂微积分';

  @override
  String get mainQuests => '主线任务';

  @override
  String get makeLessonCard => '生成教训卡';

  @override
  String get mapEmptyLine => '还没有任务线。告诉向导你想学什么。';

  @override
  String get mapTapNode => '点一个节点开始挑战。';

  @override
  String get meals => '饮食';

  @override
  String get menu => '菜单';

  @override
  String get messageHint => '输入消息…';

  @override
  String get misconception => '误解';

  @override
  String get myCharacter => '我的角色';

  @override
  String get navHowItWorks => '怎么玩';

  @override
  String get newHere => '第一次来？';

  @override
  String get newNodesUnlocked => '解锁了新节点';

  @override
  String get next => '下一页';

  @override
  String get noAttemptsYet => '还没有尝试记录。';

  @override
  String get noAuditsYet => '还没有审核记录。';

  @override
  String get noConversationYet => '还没有对话。';

  @override
  String get noCourseServesQuest => '还没有课程归属这个任务。';

  @override
  String get noDescriptionYet => '还没有简介。';

  @override
  String get noMatchingNode => '没有匹配的节点。';

  @override
  String get noQuestLineYet => '还没有任务线';

  @override
  String get node => '节点';

  @override
  String get notQuite => '还差一点。';

  @override
  String get onbBegin => '开始';

  @override
  String get onbBuildFailed => '这个世界没能建好。再试一次，或者先跳过。';

  @override
  String get onbBuildIt => '开始搭建';

  @override
  String get onbBuildingBody => '我会找一份真实的课程大纲，把它变成一棵等你证明的知识树。可能要花一分钟。';

  @override
  String get onbBuildingTitle => '正在搭建你的世界……';

  @override
  String get onbCourseKicker => '第一门课';

  @override
  String get onbDoneGuide => '好了。';

  @override
  String get onbFlipGuide => '现在反过来想。';

  @override
  String get onbHiGuide => '你好，我是你的向导。';

  @override
  String get onbIdentityHelper => '就当它已经是真的来写。';

  @override
  String get onbIdentityKicker => '身份';

  @override
  String get onbIdentityTitle => '把这句话补完。';

  @override
  String get onbLearnFirst => '你想先学什么？';

  @override
  String onbLearnFirstFor(String quest) {
    return '为了「$quest」，你需要先学什么？';
  }

  @override
  String get onbMomentGuide => '稍等一下。';

  @override
  String get onbNeedTopic => '告诉我一个主题，或者选一个课程大纲文件。';

  @override
  String onbNodesToProve(int count) {
    return '有 $count 个节点等你证明。';
  }

  @override
  String onbNodesToProveUnder(int count, String quest) {
    return '「$quest」下有 $count 个节点等你证明。';
  }

  @override
  String get onbQuestGuide => '选一个今年的任务。';

  @override
  String get onbQuestHelper => '最多可以有三个。开始时一个就够了。';

  @override
  String get onbQuestKicker => '主线任务';

  @override
  String get onbQuestTitle => '有什么目标能让你离胜利条件更近一步？';

  @override
  String get onbSetUpCharacter => '来设定你的角色吧。';

  @override
  String get onbSkillsGuide => '每个任务都需要技能。';

  @override
  String get onbSkipSetup => '跳过设置';

  @override
  String get onbStakesGuide => '先说说你要付出的代价。';

  @override
  String get onbStakesHelper => '说实话。这就是你要对抗的东西。';

  @override
  String get onbStakesHint => '又一年的……';

  @override
  String get onbStakesKicker => '代价';

  @override
  String get onbStakesTitle => '一年后，什么都没变。你的生活是什么样？';

  @override
  String onbStepOf(int step, int total) {
    return '第 $step 步，共 $total 步';
  }

  @override
  String get onbTopicBody => '给个主题就够了。有课程大纲？那就直接用文件（PDF、TXT 或 MD）。';

  @override
  String get onbTopicHint => '例如：微积分';

  @override
  String get onbUseSyllabusFile => '使用课程大纲文件';

  @override
  String onbWantToLearn(String topic) {
    return '我想学$topic';
  }

  @override
  String get onbWantToLearnThis => '我想学这个';

  @override
  String get onbWelcomeBody =>
      '在 Self-Infinity 里，你靠证明自己真的懂了来升级：用自己的话讲出来，由审核官来判定。先回答几个问题，每个一两句话就行（打字，或者点麦克风说出来）；之后都可以改。';

  @override
  String get onbWhoGuide => '谁能做到？';

  @override
  String get onbWinHelper => '具体比厉害更重要。';

  @override
  String get onbWinHint => '我能……';

  @override
  String get onbWinKicker => '胜利条件';

  @override
  String get onbWinTitle => '一年后，你赢了。那是什么样子？';

  @override
  String onbWorldReady(String course) {
    return '你的世界「$course」准备好了。';
  }

  @override
  String get openLifeTree => '打开人生树';

  @override
  String get openNode => '打开节点';

  @override
  String get orDivider => '或';

  @override
  String get pageNotFound => '找不到这个页面';

  @override
  String get password => '密码';

  @override
  String passwordWithMin(int count) {
    return '密码（至少 $count 个字符）';
  }

  @override
  String points(int score) {
    return '$score 分';
  }

  @override
  String get pointsUnit => '分';

  @override
  String get previous => '上一页';

  @override
  String questProgress(int done, int total, int count) {
    return '$count 门课程共 $total 个节点，已通关 $done 个。';
  }

  @override
  String get readyToTry => '准备好试试了吗？';

  @override
  String get recorderAsk => '你哪里理解错了？';

  @override
  String get recorderTagline => '把失误变成教训';

  @override
  String get removeMainQuest => '删除主线任务';

  @override
  String get removeRule => '删除规则';

  @override
  String get renameUnderCharacter => '可以在「我的角色」里改名或删除。';

  @override
  String get replayTutorial => '重看新手教程';

  @override
  String resetLinkSent(String email) {
    return '我们已向 $email 发送了重置密码的链接。';
  }

  @override
  String get resources => '资料';

  @override
  String get robotAlt => '一个机器人，掌心托着你的人生树';

  @override
  String get rulePlaceholder => '例如：第一次审核前不碰手机';

  @override
  String get rules => '规则';

  @override
  String get sampleCalculus => '微积分';

  @override
  String get sampleClarity => '清晰';

  @override
  String get sampleDerivatives => '导数';

  @override
  String get sampleInference => '推断';

  @override
  String get sampleIntegrals => '积分';

  @override
  String get sampleLimits => '极限';

  @override
  String get sampleProbability => '概率';

  @override
  String get sampleStatistics => '统计';

  @override
  String get sampleStructure => '结构';

  @override
  String get sampleWriting => '写作';

  @override
  String saveFailed(String error) {
    return '保存失败。$error';
  }

  @override
  String get scrollHint => '向下滚动';

  @override
  String get search => '搜索';

  @override
  String get searchNodesHint => '搜索节点…';

  @override
  String get seeOutline => '查看大纲 →';

  @override
  String get send => '发送';

  @override
  String get serves => '所属任务';

  @override
  String get showPassword => '显示密码';

  @override
  String get sideQuest => '支线任务';

  @override
  String get sideQuestCourse => '支线任务 · 课程';

  @override
  String get sideQuestNone => '支线任务（不归属）';

  @override
  String get signIn => '登录';

  @override
  String get signInBlurb => '登录后从上次停下的地方继续。';

  @override
  String get signOut => '退出登录';

  @override
  String get signUpBlurb => '你的树、教训和规则都会保存在你的账户里。';

  @override
  String get signedInAs => '当前登录';

  @override
  String get skip => '跳过';

  @override
  String get sleep => '睡眠';

  @override
  String get somethingWentWrong => '出了点问题，请再试一次。';

  @override
  String get somethingWentWrongShort => '出了点问题。';

  @override
  String sourceLabel(String source) {
    return '来源：$source';
  }

  @override
  String get speakYourAnswer => '用语音回答';

  @override
  String get stakes => '代价';

  @override
  String get stakesPlaceholder => '如果什么都不改变会怎样？';

  @override
  String get startAudit => '开始审核';

  @override
  String get stats => '属性';

  @override
  String get stopListening => '停止听写';

  @override
  String get takeItOn => '开始挑战';

  @override
  String get today => '今天';

  @override
  String get tourBallBody => '你在中间，任务围着你，技能在更外圈。在首页点一下水晶球，就能打开完整的树。';

  @override
  String get tourBallKicker => '你的水晶球';

  @override
  String get tourBallTitle => '整棵人生树，都在一个球里。';

  @override
  String get tourLessonsBody => '审核没通过时，写下你错在哪里。它会变成一张教训卡，审核官下次会记得。';

  @override
  String get tourLessonsKicker => '教训';

  @override
  String get tourLessonsTitle => '每次失误都会变成教训。';

  @override
  String get tourNext => '下一步';

  @override
  String get tourProveBody => '打开一个点，用自己的话讲清楚。审核官会一直追问，直到确定你真的懂了。然后这个点就会变成金色。';

  @override
  String get tourProveKicker => '证明它';

  @override
  String get tourProveTitle => '讲出来，审核官来判定。';

  @override
  String get treeStartsWithYou => '你的树从你开始。';

  @override
  String get tryAgain => '重试';

  @override
  String get uploadBadFile => '仅支持 4 MB 以内的 PDF、TXT 或 MD 文件。';

  @override
  String get uploadFile => '上传文件';

  @override
  String uploadTooMany(int count) {
    return '最多可以附加 $count 个文件。';
  }

  @override
  String get uploadedCourseMaterial => '上传的课程资料';

  @override
  String get uploading => '上传中…';

  @override
  String get verdict => '结论';

  @override
  String get verdictCleared => '通过了。';

  @override
  String get verdictNotYet => '还没通过。';

  @override
  String get viewFrontPage => '查看首页';

  @override
  String get viewOutline => '大纲';

  @override
  String get viewTree => '树';

  @override
  String get voiceListening => '正在听…';

  @override
  String get voiceMode => '语音模式';

  @override
  String get voiceModeUnavailable => '这台设备不支持语音模式。';

  @override
  String get voiceSpeaking => '正在说…';

  @override
  String get voiceTapToTurnOff => '点按关闭语音模式';

  @override
  String get voiceThinking => '思考中…';

  @override
  String get voiceUnavailable => '这台设备不支持语音输入。';

  @override
  String get welcomeBack => '欢迎回来';

  @override
  String get whatWasMissing => '缺了什么';

  @override
  String get whatWentWrongHint => '你错在哪里？…';

  @override
  String get winCondition => '胜利条件';

  @override
  String get winConditionPlaceholder => '赢了是什么样子？';

  @override
  String get worthSecondLook => '值得再看一眼';

  @override
  String get you => '你';
}
