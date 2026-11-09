// Shots — ギャラリーの場面（make render-all の 1 枚）の World を組む。描き出し（SceneRender）と実機（Game の App.withShots。
// START=shot:<場面>）が同じ関数で組むので、実機で開いた場面はギャラリーの絵と同じ World から始まる。
// 場面は「進めて作る」: 台本が伸びても行番号を数え直さずに済むよう、「ノードの n 番目の台詞」「選択肢が出るまで」で位置を決める。
// WhyNot: 描き出しの物（HeadlessRender・HeadlessFont・java.io）を引かない — Game.app から engine_tools へつながり、ブラウザ版で組めなくなる。
mod Shots {
    use fge::{Clock, Emit, Yarn, YarnRunner, YarnStorage}

    /// 描き出しの始まりの World（セーブデータは空・時刻は clockBase）。
    def initialOf(res: Res.Res): World.World = World.initial(Saves.fresh(res#kind), clockBase())

    /// 描き出しの「起動した時刻」（2026/08/14 19:32。セーブの日時を毎回同じ字にする）。
    pub def clockBase(): Int64 = 1786735920i64

    /// 描き出せる場面の名前（make render の SHOT とギャラリーの並びの正）。
    pub def names(): List[String] =
        "title" :: "nvl" :: "woman" :: "face" :: "phone" :: "hold" :: "log" :: "save" :: "load" :: "settings" :: "ask" :: "credits" :: Nil

    /// 名前 → 描き出しと同じ初めの World（initialOf）から組んだ場面の World。
    pub def worldOf(name: String, res: Res.Res): Option[World.World] = sceneOf(res, name, initialOf(res))

    /// 名前 → その場面の World。時計は秒で据える（蛍もクレジットも実時間から導くので、据えれば毎回同じ絵）。
    def sceneOf(res: Res.Res, name: String, w0: World.World): Option[World.World] =
        match name {
            case "title"    => Some(at(3.0, w0))
            case "nvl"      => Some(at(4.0, nthLine(res, "Opening", 1, w0)))
            case "woman"    => Some(at(4.0, nthLine(res, "Woman", 1, w0)))
            case "face"     => Some(at(4.0, nthLine(res, "Face", 1, w0)))
            case "phone"    => Some(at(4.0, nthLine(res, "Call", 1, w0)))
            // 素材の待ち: ブラウザ版で次の写真がまだ届かず、黒のまま待っている所（右下に待ちの印）。
            case "hold"     => Some(at(4.0, holding(res, nthLine(res, "Opening", 1, w0))))
            case "log"      =>
                let w = quiet(() -> WorldLog.openLog(readThrough(res, w0)));
                Some(at(4.0, { pointer = { x = 270.0, y = 300.0 } | w }))
            case "save"     => Some(at(4.0, quiet(() -> WorldSaves.openSave(withSlots(res, nthLine(res, "Store", 2, w0))))))
            case "load"     => Some(at(4.0, quiet(() -> WorldSaves.openLoad(World.toTitle(withSlots(res, w0))))))
            case "settings" => Some(at(1.2, quiet(() -> WorldSettings.openSettings(nthLine(res, "Kitchen", 1, w0)))))
            case "ask"      => Some(at(4.0, quiet(() -> World.askFor(World.Ask.ToTitle, nthLine(res, "Kitchen", 1, w0)))))
            // クレジット: 流れ始めて 12 秒（写真の出典が見えている所）。
            case "credits"  => Some(at(12.0, World.toCredits(res, w0)))
            case _          => None
        }

    /// 次の写真（寝室）を黒のまま待ち続けている形（待ちの印が出る長さだけ待った所）。
    def holding(res: Res.Res, w: World.World): World.World =
        let names = BackdropDoc.textureOf("bedroom", res#backdrops) |> Option.toList;
        let hold = { phase = World.HoldPhase.Waiting, phaseFrom = World.now(w), waited = KindDoc.rec(res#kind)#holdMarkSeconds + 1.0,
                     names = names, rest = Nil, last = None };
        World.mapRead(r -> { hold = Some(hold) | r }, w)

    /// 物語の時計と実時間の今を、どちらも seconds 秒に据える。
    def at(seconds: Float64, w: World.World): World.World =
        { storyClock = Clock.startAt(seconds), realNow = Clock.after(seconds, Clock.zero()) | w }

    def quiet(f: Unit -> World.World \ Emit[World.Event]): World.World = fst(Emit.collect(f))

    /// node の上から n 番目（0 から）の台詞を出し終えた所（その行までのコマンドは反映して、演出は終わりの形）。
    def nthLine(res: Res.Res, node: String, n: Int32, w: World.World): World.World =
        let line = Yarn.nodeOf(node, res#dialogue)
            |> Option.map(found -> found#body |> List.filterMap(statement -> match statement {
                   case Yarn.Statement.Say(say) => Some(say#source#line)
                   case _                       => None
               }))
            |> Option.flatMap(List.nth(n)) |> Option.getWithDefault(0);
        WorldRead.revealLine(quiet(() -> WorldRead.openAt(res, YarnStorage.empty(), node, line, w)))

    /// 1 ページ目に 3 つ（キッチン・居間・朝）、オートのページに 1 つセーブした World。日時は少しずつずらす。
    def withSlots(res: Res.Res, w: World.World): World.World =
        let saveAt = (minutes: Int64, i: Int32, scene: World.World, target: World.World) ->
            { saves = quiet(() -> WorldSaves.writeSlot(res, Saves.Tab.Numbered(1), i, { saves = target#saves, clockBase = clockBase() + minutes * 60i64 | scene }))#saves | target };
        w |> saveAt(-2900i64, 0, nthLine(res, "Kitchen", 1, w))
          |> saveAt(-2860i64, 1, nthLine(res, "Woman", 1, w))
          |> saveAt(-12i64, 2, nthLine(res, "Morning", 2, w))
          |> (cur -> { toast = None | cur })

    /// はじめから少し読み進めた World（バックログに何行も積むため。文字送りは待たない）。
    def readThrough(res: Res.Res, w: World.World): World.World =
        def walk(fuel: Int32, picks: List[Int32], cur: World.World): World.World =
            if (fuel <= 0) cur
            else if (World.isChoosing(cur)) match picks {
                case i :: rest => walk(fuel - 1, rest, quiet(() -> WorldRead.pick(res, i, cur)))
                case Nil       => cur
            }
            else walk(fuel - 1, picks, settleWait(res, quiet(() -> WorldRead.advance(res, WorldRead.revealLine(cur)))));
        walk(14, Nil, settleWait(res, quiet(() -> WorldRead.newGame(res, w))))

    /// <<wait>> を明かす（描き出しは時計を進めないので、明ける時刻で 1 歩だけ流す）。
    def settleWait(res: Res.Res, w: World.World): World.World =
        match World.readOf(w) |> Option.flatMap(r -> YarnRunner.waitUntilOf(r#talk)) {
            case Some(until) => quiet(() -> WorldRead.step(res, 0.0, { storyClock = Clock.startAt(Clock.secondsOf(until)) | w }))
            case None        => w
        }
}
