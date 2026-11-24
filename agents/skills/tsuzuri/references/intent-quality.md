# 執筆意図の質の確認

このファイルは執筆意図を決定する前に見直すときと、指摘レビューで執筆意図を確認するときに参照します。
記述しているのは、執筆意図そのものが成り立っているかを確認する問い2つと、その理由です。
項目を1つずつ当てるチェックリストとしては使用しないでください。
初心者の推敲は語の表面に規則を当てるだけで、目的と読み手を問う手順を持たないと報告されていて（Sommers 1980）、執筆意図の言葉づかいが自然でも内容が不適切であることは、規則を当てても発見できません。

## 一文ごとの問い：だから何か

一文ごとの執筆意図には次を問いかけてください。

> この執筆意図を果たしたとき、読み手は何を得ますか。読み手が「だから何？」と思ったとき、この文はそれに答えていますか。

この問いは、語りの研究で読み手の「だから何？」に答える部分を評価（evaluation）と呼ぶ考え方によります（Labov）。
この問いは読み手を1人に限定しなくても使用できるため、一文ごとの確認にはこの問いだけを使用してください。
答えられないときは、次の3つの方向から理由を考えてください（理由を考える手がかりで、確認の項目ではありません）。

- 執筆意図が読み手に渡すものではなく、書き手が考えた順序や書き手の都合を映していないか（Flower 1979 の Writer-Based prose、思い出した順に書く knowledge telling：Bereiter & Scardamalia 1987）。
- 執筆意図が2通りに解釈でき、どちらの意味かを判断する仕事が読み手に移っていないか（読み手はただ読むのではなく解釈する：Gopen & Swan 1990）。
- 執筆意図に複数の目的が含まれていて、文がどれを果たしたのかが定まらないか。

成り立たないと判明したら、文より先に執筆意図を修正してください。
執筆意図が成り立たないまま文だけを修正すると、文は執筆意図に合っても、読み手に渡すものが無いままになります。

### 答えられないときは上へたどる

執筆意図が「だから何？」に答えられないときは、その執筆意図が設計書の段落や要件定義書の項目をそのまま写していないかを確認してください。
写しているなら、答えられない原因は文ではなく設計書か要件定義書にあるため、指摘はその段落か項目に付けてください。
元をそのままにして文だけを修正すると、同じ問題が同じ段落から執筆したほかの文にも生じます。
答えられている文については設計書や要件定義書を疑う指摘を出さないでください。

## 要件定義書の段階の問い：誰がたどり着くか

読み手については要件定義書を決定する段階で1回だけ、次を問いかけてください。

> この文章はどこで公開されますか。読み手はどのようにしてそこへたどり着きますか。たどり着く人に、どんな幅がありますか。

読み手を、属性だけで決定しないでください。
実際に読む人（audience addressed）と書き手が思い描いた読み手（audience invoked）は別のもので（Ede & Lunsford 1984）、属性だけで決定した読み手は、公開した場所で実際に届く読み手と乖離します。
誰でも閲覧できる場所では読み手が1種類に定まらないため（Marwick & boyd 2010 の context collapse）、読み手は1人に絞らず、幅のまま記述してください。

要件定義書の段階では執筆する内容の各項目にも「この項目を記述したとき、読み手は何を得ますか」と問いかけてください。
「〇〇を論じる」「〇〇に触れる」のように、執筆する内容だけを決定して読み手が得るものを記述していない項目は、要件定義書の段階で修正してください。
そのまま執筆を始めると、設計書も執筆意図もその項目を写し、読み手に渡すものの無い文が並びます。

## 一文ごとの確認に読み手を用いない理由

一文ごとに「この読み手に合っているか」を確認すると、どの文も読み手に合わせて説明を追加し、言い換える方向へ修正され、書き手の声（voice）が失われます。
読み手を意識せずに執筆することを勧める論文もあります（Elbow 1987）。
要件定義書で決定した読み手の幅は、執筆意図の前提として踏まえてください。

## 出典

- Sommers, N. (1980). Revision Strategies of Student Writers and Experienced Adult Writers. *College Composition and Communication*, 31(4).
- Labov, W. Oral Narratives of Personal Experience（*Cambridge Encyclopedia of the Language Sciences* の原稿）.
- Flower, L. (1979). Writer-Based Prose: A Cognitive Basis for Problems in Writing. *College English*, 41(1).
- Bereiter, C. & Scardamalia, M. (1987). knowledge telling と knowledge transforming（McCutchen, *Journal of Writing Research* の紹介による）.
- Gopen, G. & Swan, J. (1990). The Science of Scientific Writing. *American Scientist*, 78(6).
- Ede, L. & Lunsford, A. (1984). Audience Addressed/Audience Invoked. *College Composition and Communication*, 35(2).
- Marwick, A. & boyd, d. (2010). I tweet honestly, I tweet passionately. *New Media & Society*, 13(1).
- Elbow, P. (1987). Closing My Eyes As I Speak: An Argument for Ignoring Audience. *College English*, 49(1).
