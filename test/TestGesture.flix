// 読む画面の 1 回の押しの分け方（Gesture）と、離した時だけ台詞を送ること（長押しと左の払いは送らない）をテストする。
// 押しは実機と同じ Controls.interact に、押した・押したまま動かした・離したのフレームを順に渡して作る（縦に持ったスマホの縦の画面）。
// 動いた量と秒は novel.kind.json・novel.portrait.json の数から導く（Doc の値を変えてもテストは壊れない）。
mod TestGesture {

    use fge::{App, Clock, Display, Rect2}
    use fge::GameEngine.Key
    use TestKit.{begun, quiet, settle}

    def kind(res: Res.Res): KindDoc.Rec = KindDoc.rec(res#kind)

    /// 縦に持ったスマホ（390×844）の縦の design。
    def tall(): { x = Float64, y = Float64 } = { x = 540.0, y = 1169.0 }

    def portrait(res: Res.Res): Layout.Fit =
        Layout.fitOf(Display.SizeClass.Small, Display.Orientation.Portrait, tall(), res#smallScreen, res#portrait)

    /// 頁の左の、右の列のボタンにも右上の … にも当たらない所。
    def spot(): { x = Float64, y = Float64 } = { x = 140.0, y = 640.0 }

    def shifted(dx: Float64, dy: Float64): { x = Float64, y = Float64 } = { x = spot()#x + dx, y = spot()#y + dy }

    def center(r: { position = { x = Float64, y = Float64 }, size = { x = Float64, y = Float64 } }): { x = Float64, y = Float64 } =
        { x = r#position#x + r#size#x / 2.0, y = r#position#y + r#size#y / 2.0 }

    def frameAt(at: Float64, p: { x = Float64, y = Float64 }): App.Frame =
        { cursor = p, viewport = tall(), sizeClass = Display.SizeClass.Small, dt = 0.1, realNow = Clock.after(at, Clock.zero()) | App.emptyFrame() }

    /// at 秒に p を押したフレーム。
    def down(at: Float64, p: { x = Float64, y = Float64 }): App.Frame =
        { mouseClicked = true, mouseDown = true | frameAt(at, p) }

    /// at 秒に押したまま p へ動かしたフレーム。
    def held(at: Float64, p: { x = Float64, y = Float64 }): App.Frame =
        { mouseDown = true, mouseMoved = true | frameAt(at, p) }

    /// at 秒に p で離したフレーム。
    def up(at: Float64, p: { x = Float64, y = Float64 }): App.Frame = frameAt(at, p)

    def play(res: Res.Res, frames: List[App.Frame], w: World.World): World.World =
        List.foldLeft((acc, frame) -> Controls.interact(frame, res, acc), w, frames)

    /// 押しの種類の名前（Kind は記録を持つので比べられる字へ写す）。
    def nameOf(kind: Option[Gesture.Kind]): String = match kind {
        case Some(Gesture.Kind.Tap(p))    => "Tap(${p#x},${p#y})"
        case Some(Gesture.Kind.Swipe(d))  => "Swipe(${d})"
        case Some(Gesture.Kind.LongPress) => "LongPress"
        case Some(Gesture.Kind.Drag)      => "Drag"
        case None                         => "None"
    }

    /// Gesture.step にフレームを古い順に渡し、最後のフレームで決まった種類の名前。
    def classified(res: Res.Res, frames: List[App.Frame]): String =
        let limits = KindDoc.gestureLimits(res#kind);
        frames |> List.foldLeft((acc, frame) -> Gesture.step(limits, frame, snd(acc)), (None, Gesture.idle())) |> fst |> nameOf

    // ══ 分け方 ══

    @Test
    def testGestureKindsOnRelease(): Unit \ {Assert, Fs.FileRead} =
        // 動かさずにすぐ離す = 押した所のタップ（離す所が slop 内でずれても押した所）、動かさずに長押しの秒まで置く = 長押し、
        // swipeMin を払いの秒の内に左へ = 左の払い、slop を越えてゆっくり動かす = ドラッグ。
        let res = TestKit.res();
        let k = kind(res);
        let tap = classified(res, down(0.0, spot()) :: up(0.1, shifted(k#tapSlop / 2.0, 0.0)) :: Nil);
        let long = classified(res, down(0.0, spot()) :: held(k#longPressSeconds, spot()) :: up(k#longPressSeconds, spot()) :: Nil);
        let swipe = classified(res, down(0.0, spot()) :: held(k#swipeSeconds / 2.0, shifted(0.0 - k#swipeMin, 0.0)) :: up(k#swipeSeconds / 2.0, shifted(0.0 - k#swipeMin, 0.0)) :: Nil);
        let drag = classified(res, down(0.0, spot()) :: held(k#swipeSeconds * 2.0, shifted(k#tapSlop * 2.0, 0.0)) :: up(k#swipeSeconds * 2.0, shifted(k#tapSlop * 2.0, 0.0)) :: Nil);
        Assert.assertEq(expected = ("Tap(${spot()#x},${spot()#y})", "LongPress", "Swipe(Left)", "Drag"), (tap, long, swipe, drag))

    @Test
    def testReleaseWithoutPressIsNothing(): Unit \ {Assert, Fs.FileRead} =
        // 押し始めを見ていない離し（他の画面で押した指を、ここで離した）は、どの種類にもならない。
        let res = TestKit.res();
        Assert.assertEq(expected = "None", classified(res, up(0.0, spot()) :: Nil))

    // ══ 読む画面の送り ══

    @Test
    def testTapAdvancesOnRelease(): Unit \ {Assert, Fs.FileRead} =
        // 押して動かさずに離すと 1 行送る（クリックと、ブラウザ版の指のタップ）。押しただけの拍では送らない。
        let res = TestKit.res();
        let start = begun(res);
        let pressed = play(res, down(0.0, spot()) :: Nil, start);
        let released = play(res, up(0.1, spot()) :: Nil, pressed);
        Assert.assertEq(expected = (World.talkLineOf(start), World.talkLineOf(TestKit.advance(res, start))),
                        (World.talkLineOf(pressed), World.talkLineOf(released)))

    @Test
    def testHeldMovingFingerNeverAdvances(): Unit \ {Assert, Fs.FileRead} =
        // 指を置いたまま何度動かしても（行ったり来たりして押した所へ戻っても）送らない。
        let res = TestKit.res();
        let start = begun(res);
        let k = kind(res);
        let w = play(res, down(0.0, spot()) :: held(0.2, shifted(k#tapSlop * 2.0, 0.0)) :: held(0.4, shifted(0.0, k#tapSlop * 4.0))
                          :: held(0.6, spot()) :: held(0.8, shifted(0.0 - k#tapSlop * 3.0, 0.0)) :: Nil, start);
        Assert.assertEq(expected = World.talkLineOf(start), World.talkLineOf(w))

    @Test
    def testReleasingADragAdvancesOneLine(): Unit \ {Assert, Fs.FileRead} =
        // 押したまま動かして離すと、離したフレームで 1 行だけ送る。
        let res = TestKit.res();
        let start = begun(res);
        let k = kind(res);
        let w = play(res, down(0.0, spot()) :: held(1.0, shifted(k#tapSlop * 2.0, 0.0)) :: up(1.2, shifted(k#tapSlop * 2.0, 0.0)) :: Nil, start);
        Assert.assertEq(expected = World.talkLineOf(TestKit.advance(res, start)), World.talkLineOf(w))

    @Test
    def testSwipeUpAdvancesOneLine(): Unit \ {Assert, Fs.FileRead} =
        // 意味を持たない向きの払い（swipeMin を払いの秒の内に上へ）は、ドラッグと同じく離したフレームで 1 行送る。
        let res = TestKit.res();
        let start = begun(res);
        let k = kind(res);
        let far = shifted(0.0, 0.0 - k#swipeMin * 1.5);
        let w = play(res, down(0.0, spot()) :: held(k#swipeSeconds / 2.0, far) :: up(k#swipeSeconds / 2.0, far) :: Nil, start);
        Assert.assertEq(expected = World.talkLineOf(TestKit.advance(res, start)), World.talkLineOf(w))

    @Test
    def testSwipeLeftOnlyRollsBack(): Unit \ {Assert, Fs.FileRead} =
        // 左へ払うと（ブラウザ版は離したフレームで touchGestures の swipeLeft = 戻るのキーも出る）1 行戻るだけで、戻した行から送らない。
        let res = TestKit.res();
        let first = begun(res);
        let second = settle(res, TestKit.advance(res, first));
        let k = kind(res);
        let rollback = KeysDoc.rec(res#keys)#rollback |> List.head |> Option.getWithDefault(Key.PageUp);
        let left = shifted(0.0 - k#swipeMin * 1.5, 0.0);
        let release = { justPressed = Set#{rollback}, down = Set#{rollback} | up(k#swipeSeconds / 2.0, left) };
        let w = play(res, down(0.0, spot()) :: held(k#swipeSeconds / 2.0, left) :: release :: Nil, second);
        Assert.assertEq(expected = World.talkLineOf(first), World.talkLineOf(w))

    @Test
    def testLongPressDoesNotAdvance(): Unit \ {Assert, Fs.FileRead} =
        // 動かさずに長押しの秒まで置いてから離しても送らない。
        let res = TestKit.res();
        let start = begun(res);
        let k = kind(res);
        let w = play(res, down(0.0, spot()) :: held(k#longPressSeconds, spot()) :: up(k#longPressSeconds + 0.1, spot()) :: Nil, start);
        Assert.assertEq(expected = World.talkLineOf(start), World.talkLineOf(w))

    @Test
    def testConfirmKeyAdvancesOnPress(): Unit \ {Assert, Fs.FileRead} =
        // キーの決定は押した拍に 1 行送る（押しの分け方を通らない）。
        let res = TestKit.res();
        let start = begun(res);
        let w = Controls.interact({ justPressed = Set#{Key.Enter}, down = Set#{Key.Enter}, viewport = tall() | App.emptyFrame() }, res, start);
        Assert.assertEq(expected = World.talkLineOf(TestKit.advance(res, start)), World.talkLineOf(w))

    @Test
    def testWheelDoesNotAdvance(): Unit \ {Assert, Fs.FileRead} =
        // 下へのホイールの刻み（ブラウザ版で指を置いたまま上へ動かした時）が来ても、台詞は進まない。
        let res = TestKit.res();
        let start = begun(res);
        let w = play(res, { wheel = -1.0 | frameAt(0.0, spot()) } :: { wheel = -2.0 | frameAt(0.1, spot()) } :: Nil, start);
        Assert.assertEq(expected = World.talkLineOf(start), World.talkLineOf(w))

    // ══ 他の画面は分け方に巻き込まない ══

    @Test
    def testSliderDragInSettingsChangesValueWithoutAdvancing(): Unit \ {Assert, Fs.FileRead} =
        // 読んでいる途中で設定を開き、文字の速さの帯を左端から右端へなぞって離すと、値は上限になり、台詞は進まず設定も開いたまま。
        let res = TestKit.res();
        let reading = begun(res);
        let opened = quiet(() -> WorldMenu.press(res, World.Button.Settings, reading));
        let bar = Layout.settingBar(portrait(res), 0);
        let y = bar#position#y + bar#size#y / 2.0;
        let w = play(res, down(0.0, { x = bar#position#x, y = y }) :: held(0.3, { x = bar#position#x + bar#size#x, y = y })
                          :: up(0.4, { x = bar#position#x + bar#size#x, y = y }) :: Nil, opened);
        Assert.assertEq(expected = (kind(res)#cpsSlider#max, World.talkLineOf(reading), World.panelName(opened)),
                        (Saves.configOf(w#saves)#cps, World.talkLineOf(w), World.panelName(w)))

    @Test
    def testClosingAPanelByClickDoesNotAdvanceOnRelease(): Unit \ {Assert, Fs.FileRead} =
        // 設定の戻るを押して閉じ、その指を読む画面で離しても、タップとして台詞は進まない。
        let res = TestKit.res();
        let reading = begun(res);
        let opened = quiet(() -> WorldMenu.press(res, World.Button.Settings, reading));
        let p = center(Layout.back(portrait(res)));
        let w = play(res, down(0.0, p) :: up(0.1, p) :: Nil, opened);
        Assert.assertEq(expected = ("Closed", World.talkLineOf(reading)), (World.panelName(w), World.talkLineOf(w)))

    /// ブラウザ版で指を縦に払った 1 回: 動かしている間はホイールの刻み（指を下へ = 上へ回した向き = 正）だけが来て、
    /// 離したフレームで touchGestures の swipeUp / swipeDown = advance のキーが 1 回来る。左ボタンは一度も押さない。
    def fingerSwipe(res: Res.Res, wheel: Float64, w: World.World): World.World =
        let advance = KeysDoc.rec(res#keys)#advance |> List.head |> Option.getWithDefault(Key.PageDown);
        let moving = { wheel = wheel | App.emptyFrame() };
        let release = { justPressed = Set#{advance}, down = Set#{advance} | App.emptyFrame() };
        play(res, moving :: moving :: release :: Nil, w)

    @Test
    def testVerticalFingerSwipesAdvanceOneLineEach(): Unit \ {Assert, Fs.FileRead} =
        // 下へ払っても上へ払っても、1 行だけ送り、バックログは開かない（離した時の 1 行送りと押しの分け方とで 2 重に送らない）。
        let res = TestKit.res();
        let start = begun(res);
        let pulled = fingerSwipe(res, 1.0, start);
        let pushed = fingerSwipe(res, -1.0, start);
        let once = World.talkLineOf(TestKit.advance(res, start));
        Assert.assertEq(expected = ((once, "Closed"), (once, "Closed")),
                        ((World.talkLineOf(pulled), World.panelName(pulled)), (World.talkLineOf(pushed), World.panelName(pushed))))

    @Test
    def testWheelUpWhileReadingDoesNotOpenTheLog(): Unit \ {Assert, Fs.FileRead} =
        // 読んでいる間に上へホイールを回しても、バックログは開かず台詞も進まない（ログは画面のボタンとキーで開く）。
        let res = TestKit.res();
        let start = begun(res);
        let w = play(res, { wheel = 1.0 | App.emptyFrame() } :: Nil, start);
        Assert.assertEq(expected = ("Closed", World.talkLineOf(start)), (World.panelName(w), World.talkLineOf(w)))

    def isTitle(w: World.World): Bool = match w#scene {
        case World.Scene.Title(_) => true
        case _                    => false
    }

    @Test
    def testAdvanceKeyDoesNothingOnTitle(): Unit \ {Assert, Fs.FileRead} =
        // タイトルで縦に払っても（決定と違って）カーソルの項目を選ばず、タイトルのまま。
        let res = TestKit.res();
        let w = fingerSwipe(res, 1.0, TestKit.w0(res));
        Assert.assertTrue(isTitle(w))

    def logOffsetOf(w: World.World): Float64 = match w#panel {
        case World.Panel.Log(offset) => offset
        case _                       => -1.0
    }

    @Test
    def testWheelUpScrollsTheLog(): Unit \ {Assert, Fs.FileRead} =
        // バックログの中で上へホイールを回すと、遡る（閉じない）。
        let res = TestKit.res();
        let read = List.range(0, 12) |> List.foldLeft((acc, _) -> TestKit.settle(res, TestKit.advance(res, acc)), begun(res));
        let opened = quiet(() -> WorldLog.openLog(read));
        let w = play(res, { wheel = 1.0 | App.emptyFrame() } :: Nil, opened);
        Assert.assertTrue(logOffsetOf(w) > logOffsetOf(opened))

    /// 設定の行 i で、最大にしたつまみ（選んだ時の半径 8）の矩形と、右に寄せた一番長い値の字「ノーウェイト」（全角 1 字 = 字の大きさ 1 つ分）の矩形。
    def knobAndLongestValue(fit: Layout.Fit, i: Int32): (Rect2.Rect2, Rect2.Rect2) =
        let bar = Layout.settingBar(fit, i);
        let row = Layout.settingRow(fit, i);
        let text = Layout.settingText(fit);
        let width = Int32.toFloat64(String.length("ノーウェイト")) * text#value;
        let knob = { position = { x = bar#position#x + bar#size#x - 8.0, y = bar#position#y + bar#size#y / 2.0 - 8.0 }, size = { x = 16.0, y = 16.0 } };
        let value = { position = { x = row#position#x + row#size#x - width, y = row#position#y + text#valueTop }, size = { x = width, y = text#value } };
        (knob, value)

    def sliderRow(i: Int32, setting: World.Setting): Option[Int32] = match setting {
        case World.Setting.Slider(_) => Some(i)
        case _                       => None
    }

    def overlaps(a: Rect2.Rect2, b: Rect2.Rect2): Bool =
        a#position#x < b#position#x + b#size#x and b#position#x < a#position#x + a#size#x and
        a#position#y < b#position#y + b#size#y and b#position#y < a#position#y + a#size#y

    def knobsTouchingTheLongestValue(fits: List[Layout.Fit]): Int32 =
        let sliders = WorldSettings.settings() |> List.zipWithIndex |> List.filterMap(match (i, setting) -> sliderRow(i, setting));
        fits |> List.flatMap(fit -> sliders |> List.map(knobAndLongestValue(fit)))
             |> List.count(match (knob, value) -> overlaps(knob, value))

    @Test
    def testSliderKnobNeverTouchesTheLongestValueText(): Unit \ {Assert, Fs.FileRead} =
        // 横・横持ちのスマホ・縦（細長い・太い）のどれでも、どのスライダーの行でも、最大にしたつまみと一番長い値の字が重ならない。
        let res = TestKit.res();
        let fits = Layout.Fit.Regular :: Layout.fitOf(Display.SizeClass.Small, Display.Orientation.Landscape, Layout.size(Layout.Fit.Regular), res#smallScreen, res#portrait)
                   :: Layout.fitOf(Display.SizeClass.Small, Display.Orientation.Portrait, { x = 540.0, y = 1169.0 }, res#smallScreen, res#portrait)
                   :: Layout.fitOf(Display.SizeClass.Small, Display.Orientation.Portrait, { x = 540.0, y = 960.0 }, res#smallScreen, res#portrait) :: Nil;
        Assert.assertEq(expected = 0, knobsTouchingTheLongestValue(fits))
}
