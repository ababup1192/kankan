// Stage — 舞台（背景・暗転・白飛び・揺れ・寄り・字の置き場・環境音）の状態と、シナリオのコマンドからの反映のし方（純粋）。
// シナリオに書けるコマンド（Talk の語彙。check は名前だけを見るので、引数はここが読む）:
//
//   <<bg 写真 時間帯 秒>>     背景を「写真」（BackdropDoc の photos）に「時間帯」（grades）の色で替え、秒かけて重ねる。秒は省ける（1 秒）
//   <<nvl>> / <<adv>>         文章を画面いっぱいに積む / 下のウィンドウに 1 行ずつ出す
//   <<clear>>                 NVL の頁をめくる（ADV では何もしない）
//   <<ambience 名>>           鳴り続ける環境音を amb_<名> に替える（off で止める）
//   <<se 名>>                 効果音 se_<名> を 1 回（音は World が出来事にして鳴らす）
//   <<fx 名>>                 画面のパーティクルの演出（off で止める）
//   <<shake>> / <<shake big>> 画面を揺らす（big は長く大きく、字も揺れる）
//   <<dim 濃さ 秒>>           背景に被せる黒の濃さを秒かけて変える（字は黒の上に出る）
//   <<flash 秒>>              白く光って秒かけて消える
//   <<zoom 倍率 秒>>          背景を秒かけて寄せる（秒 0 ですぐ）
//   <<text 位置 大きさ 揃え>> 字の置き場 top / mid / bottom・大きさ small / normal / large / huge・揃え left / center
//   <<speed 倍率>>            字の出る速さの倍率
//   <<hold 秒>>               秒の間、タップで字を飛ばせなくする
//
// 引数の読めないコマンドは Err で返し、World が 1 行知らせて舞台はそのまま続ける（シナリオの書き損じで止めない）。
// セーブから戻る時は YarnRunner.resume が通ったコマンドを全部返すので、同じ applyCue で反映してから settle で
// 演出の途中を終わりの形にする（背景は重ね終わり・暗転は目標の濃さ・寄りは目標の倍率・揺れは止まる）。
mod Stage {
    use fge::{Clock, Num, Vec2, Yarn}

    /// 物語の時計の名前（中身は要らない）。文字送り・<<wait>>・背景の重ね・揺れが使い、画面や確認のウィンドウを開くと止まる。
    pub enum Story

    /// 文章の出し方。Nvl = 画面いっぱいに積む（小説の頁）、Adv = 下のウィンドウに 1 行ずつ。
    pub enum Mode with Eq, ToString {
        case Nvl
        case Adv
    }

    /// 字の置き場。
    pub enum TextPos with Eq, ToString {
        case Top
        case Mid
        case Bottom
    }

    /// 字の大きさの段。
    pub enum TextSize with Eq, ToString {
        case Small
        case Normal
        case Large
        case Huge
    }

    /// 字の揃え。
    pub enum TextAlign with Eq, ToString {
        case Left
        case Center
    }

    /// 揺れの強さ。Big は長く大きく、字も一緒に揺れる。
    pub enum ShakeKind with Eq, ToString {
        case Light
        case Big
    }

    /// 背景 1 枚（写真と時間帯の名前）。
    pub type alias Shot = { photo = String, grade = String }

    /// 字の見せ方の組。
    pub type alias TextStyle = { pos = TextPos, size = TextSize, align = TextAlign }

    /// 時間をかけて initial から target へ移る数。start = 移り始めた時刻、seconds = 長さ。
    pub type alias Ramp = { initial = Float64, target = Float64, start = Clock.Time[Story], seconds = Float64 }

    /// コマンド 1 つの意味。
    pub enum Cue {
        case Backdrop(Shot, Float64)
        case ToMode(Mode)
        case Clear
        case Ambience(Option[String])
        case Se(String)
        case Particles(Option[String])
        case Shake(ShakeKind)
        case Dim(Float64, Float64)
        case Flash(Float64)
        case Zoom(Float64, Float64)
        case Text(TextStyle)
        case Speed(Float64)
        case Hold(Float64)
    }

    /// 舞台。shot = 今の背景、under = 重ねている間だけ下に残す前の背景、underZoom = 前の背景の寄りの倍率、
    /// fadeFrom / fadeSeconds = 重ね始めた時刻と長さ、mode = 文章の出し方、ambience = 鳴り続ける環境音の名前、
    /// particles = パーティクルの演出の名前、shakeFrom = 揺れ始めた時刻と強さ、dim = 黒の濃さ、flash = 白飛びの始まりと長さ、
    /// zoom = 背景の寄りの倍率、text = 字の見せ方、speed = 字の出る速さの倍率、hold = 効果音を聞かせる間、送りを受けない時刻。
    pub type alias Stage = {
        shot = Option[Shot],
        under = Option[Shot],
        underZoom = Float64,
        fadeFrom = Clock.Time[Story],
        fadeSeconds = Float64,
        mode = Mode,
        ambience = Option[String],
        particles = Option[String],
        shakeFrom = Option[(Clock.Time[Story], ShakeKind)],
        dim = Ramp,
        flash = Option[(Clock.Time[Story], Float64)],
        zoom = Ramp,
        text = TextStyle,
        speed = Float64,
        hold = Option[Clock.Time[Story]]
    }

    def restAt(value: Float64): Ramp = { initial = value, target = value, start = Clock.never(), seconds = 0.0 }

    /// 物語を始める前の舞台（背景なし・NVL・音なし）。
    pub def empty(): Stage =
        { shot = None, under = None, underZoom = 1.0, fadeFrom = Clock.never(), fadeSeconds = 0.0, mode = Mode.Nvl,
          ambience = None, particles = None, shakeFrom = None, dim = restAt(0.0), flash = None, zoom = restAt(1.0),
          text = { pos = TextPos.Bottom, size = TextSize.Normal, align = TextAlign.Left }, speed = 1.0, hold = None }

    /// Talk の語彙に載せるコマンドの名前（wait はエンジンが読むので入れない）。
    pub def commandNames(): List[String] =
        "bg" :: "nvl" :: "adv" :: "clear" :: "ambience" :: "se" :: "fx" :: "shake" :: "dim" :: "flash" :: "zoom" :: "text" :: "speed" :: "hold" :: Nil

    /// 環境音の名前（<<ambience 名>> の名）→ project.json の sounds の名前。
    pub def ambienceSound(name: String): String = "amb_${name}"

    /// パーティクルの演出の名前（<<fx 名>> に書ける物）。
    pub def particleNames(): List[String] = "fireflies" :: Nil

    def posOf(text: String): Option[TextPos] = match text {
        case "top"    => Some(TextPos.Top)
        case "mid"    => Some(TextPos.Mid)
        case "bottom" => Some(TextPos.Bottom)
        case _        => None
    }

    def sizeOf(text: String): Option[TextSize] = match text {
        case "small"  => Some(TextSize.Small)
        case "normal" => Some(TextSize.Normal)
        case "large"  => Some(TextSize.Large)
        case "huge"   => Some(TextSize.Huge)
        case _        => None
    }

    def alignOf(text: String): Option[TextAlign] = match text {
        case "left"   => Some(TextAlign.Left)
        case "center" => Some(TextAlign.Center)
        case _        => None
    }

    /// 字の大きさの段を、本文の字に掛ける倍率へ。
    pub def scaleOf(size: TextSize): Float64 = match size {
        case TextSize.Small  => 0.8
        case TextSize.Normal => 1.0
        case TextSize.Large  => 1.45
        case TextSize.Huge   => 2.0
    }

    /// コマンドの意味を読む。写真・時間帯の名前は backdrops にあるかまで見る（無い名前で背景が消えないように）。
    pub def cueOf(backdrops: BackdropDoc.Doc, command: Yarn.Command): Result[String, Cue] =
        let at = " (${Yarn.sourceText(command#source)})";
        let two = (a, b, make) -> match (Float64.fromString(a), Float64.fromString(b)) {
            case (Some(x), Some(y)) => Ok(make(x, Float64.max(0.0, y)))
            case _                  => Err("<<${command#name}>> の引数が数でない${at}")
        };
        match (command#name, command#args) {
            case ("bg", photo :: grade :: rest) =>
                let seconds = match rest {
                    case text :: _ => Float64.fromString(text)
                    case Nil       => Some(1.0)
                };
                if (Option.isEmpty(BackdropDoc.photoOf(photo, backdrops))) Err("知らない写真 '${photo}'${at}")
                else if (Option.isEmpty(BackdropDoc.gradeOf(grade, backdrops))) Err("知らない時間帯 '${grade}'${at}")
                else match seconds {
                    case Some(s) => Ok(Cue.Backdrop({ photo = photo, grade = grade }, Float64.max(0.0, s)))
                    case None    => Err("<<bg>> の秒が数でない${at}")
                }
            case ("bg", _)              => Err("<<bg 写真 時間帯 秒>> の写真と時間帯が無い${at}")
            case ("nvl", _)             => Ok(Cue.ToMode(Mode.Nvl))
            case ("adv", _)             => Ok(Cue.ToMode(Mode.Adv))
            case ("clear", _)           => Ok(Cue.Clear)
            case ("ambience", "off" :: _) => Ok(Cue.Ambience(None))
            case ("ambience", name :: _) => Ok(Cue.Ambience(Some(name)))
            case ("se", name :: _)      => Ok(Cue.Se(name))
            case ("fx", "off" :: _)     => Ok(Cue.Particles(None))
            case ("fx", name :: _)      =>
                if (List.memberOf(name, particleNames())) Ok(Cue.Particles(Some(name)))
                else Err("知らないパーティクルの演出 '${name}'${at}")
            case ("shake", "big" :: _)  => Ok(Cue.Shake(ShakeKind.Big))
            case ("shake", _)           => Ok(Cue.Shake(ShakeKind.Light))
            case ("dim", a :: b :: _)   => two(a, b, (x, y) -> Cue.Dim(Float64.max(0.0, Float64.min(1.0, x)), y))
            case ("zoom", a :: b :: _)  => two(a, b, (x, y) -> Cue.Zoom(Float64.max(1.0, x), y))
            case ("flash", a :: _)      => two(a, "0", (x, _) -> Cue.Flash(x))
            case ("speed", a :: _)      => two(a, "0", (x, _) -> Cue.Speed(Float64.max(0.05, x)))
            case ("hold", a :: _)       => two(a, "0", (x, _) -> Cue.Hold(x))
            case ("text", p :: s :: a :: _) =>
                match (posOf(p), sizeOf(s), alignOf(a)) {
                    case (Some(pos), Some(size), Some(align)) => Ok(Cue.Text({ pos = pos, size = size, align = align }))
                    case _ => Err("<<text 位置 大きさ 揃え>> の名前が読めない${at}")
                }
            case (name, _)              => Err("<<${name}>> の引数が足りない${at}")
        }

    /// 移りの今の値（なめらかに始まり、なめらかに収まる）。
    pub def rampNow(now: Clock.Time[Story], ramp: Ramp): Float64 =
        if (ramp#seconds <= 0.0) ramp#target
        else {
            let t = Float64.max(0.0, Float64.min(1.0, Clock.since(ramp#start, now) / ramp#seconds));
            ramp#initial + (ramp#target - ramp#initial) * (t * t * (3.0 - 2.0 * t))
        }

    def rampTo(now: Clock.Time[Story], to: Float64, seconds: Float64, ramp: Ramp): Ramp =
        { initial = rampNow(now, ramp), target = to, start = now, seconds = seconds }

    /// コマンド 1 つを舞台に反映する（now = 物語の時計の今）。Clear と Se は舞台を変えない（頁と音は World が持つ）。
    pub def applyCue(now: Clock.Time[Story], cue: Cue, stage: Stage): Stage = match cue {
        case Cue.Backdrop(shot, seconds) =>
            { shot = Some(shot), under = stage#shot, underZoom = rampNow(now, stage#zoom), fadeFrom = now, fadeSeconds = seconds | stage }
        case Cue.ToMode(mode)       => { mode = mode | stage }
        case Cue.Ambience(name)     => { ambience = name | stage }
        case Cue.Particles(name)    => { particles = name | stage }
        case Cue.Shake(kind)        => { shakeFrom = Some((now, kind)) | stage }
        case Cue.Dim(to, seconds)   => { dim = rampTo(now, to, seconds, stage#dim) | stage }
        case Cue.Flash(seconds)     => { flash = Some((now, seconds)) | stage }
        case Cue.Zoom(to, seconds)  => { zoom = rampTo(now, to, seconds, stage#zoom) | stage }
        case Cue.Text(style)        => { text = style | stage }
        case Cue.Speed(rate)        => { speed = rate | stage }
        case Cue.Hold(seconds)      => { hold = Some(Clock.after(seconds, now)) | stage }
        case Cue.Clear              => stage
        case Cue.Se(_)              => stage
    }

    /// 演出の途中を終わりの形にする（セーブから戻った時・描き出しで場面を作る時）。
    pub def settle(stage: Stage): Stage =
        { under = None, fadeFrom = Clock.never(), shakeFrom = None, flash = None, hold = None,
          dim = restAt(stage#dim#target), zoom = restAt(stage#zoom#target) | stage }

    /// 効果音 name を聞かせる秒（この間は送りを受けない）。
    def holdSecondsOf(name: String): Float64 = match name {
        case "kan"      => 2.8
        case "kan_door" => 2.8
        case "kan_far"  => 2.8
        case "hit"      => 2.0
        case "ring"     => 1.1
        case "dial"     => 1.8
        case "coin"     => 0.9
        case "pick"     => 0.5
        case "hang"     => 0.5
        case "busy"     => 3.5
        case "door"     => 1.0
        case "stairs"   => 1.6
        case "run"      => 2.4
        case "laugh_woman" => 5.2
        case "laugh_mother" => 3.9
        case "creak"    => 1.8
        case "frontdoor" => 1.8
        case "autodoor" => 1.4
        case "pant"     => 1.2
        case "knock"    => 0.3
        case "switch"   => 0.3
        case _          => 0.0
    }

    /// 効果音を鳴らした時の舞台（聞かせる間だけ送りを止める）。
    pub def holdFor(now: Clock.Time[Story], name: String, stage: Stage): Stage =
        { hold = Some(Clock.after(holdSecondsOf(name), now)) | stage }

    /// 今は効果音を聞かせている間か。
    pub def isHeld(now: Clock.Time[Story], stage: Stage): Bool = match stage#hold {
        case Some(until) => Clock.since(until, now) < 0.0
        case None        => false
    }

    /// 背景の重ねの進み（0〜1。秒が 0 なら 1）。
    pub def fadeProgress(now: Clock.Time[Story], stage: Stage): Float64 =
        if (stage#fadeSeconds <= 0.0) 1.0
        else Float64.max(0.0, Float64.min(1.0, Clock.since(stage#fadeFrom, now) / stage#fadeSeconds))

    /// 白飛びの今の濃さ（0〜1）。
    pub def flashNow(now: Clock.Time[Story], stage: Stage): Float64 = match stage#flash {
        case None => 0.0
        case Some((start, seconds)) =>
            let t = Clock.since(start, now);
            if (seconds <= 0.0 or t < 0.0 or t >= seconds) 0.0 else 1.0 - t / seconds
    }

    /// 揺れのずれ（px）。揺れの長さと幅は novel.kind.json。Big は長さ 2.2 倍・幅 3 倍。だんだん収まる。
    pub def shakeOffset(now: Clock.Time[Story], seconds: Float64, px: Float64, stage: Stage): (Float64, Float64) =
        match stage#shakeFrom {
            case None       => (0.0, 0.0)
            case Some((start, kind)) =>
                let (span, amp) = if (kind == ShakeKind.Big) (seconds * 2.2, px * 3.0) else (seconds, px);
                let t = Clock.since(start, now);
                if (t < 0.0 or t >= span or span <= 0.0) (0.0, 0.0)
                else {
                    let left = 1.0 - t / span;
                    (Num.sin(t * 71.0) * amp * left, Num.cos(t * 53.0) * amp * 0.5 * left)
                }
        }

    /// 字のずれ（px）。Big の揺れの間だけ、背景の半分だけ揺れる。
    pub def textShakeOffset(now: Clock.Time[Story], seconds: Float64, px: Float64, stage: Stage): (Float64, Float64) =
        match stage#shakeFrom {
            case Some((_, ShakeKind.Big)) =>
                let (x, y) = shakeOffset(now, seconds, px, stage);
                (x * 0.5, y * 0.5)
            case _ => (0.0, 0.0)
        }
}
