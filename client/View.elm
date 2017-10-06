module View exposing (view)

-- builtin
import Json.Decode as JSD
import Json.Decode.Pipeline as JSDP

-- lib
import Svg
import Svg.Attributes as SA
import Html
import Html.Attributes as Attrs
import Html.Events as Events
import VirtualDom

-- dark
import Types exposing (..)
import Util exposing (deMaybe)
import Entry
import Graph as G
import Defaults
import Viewport
import Selection
import Autocomplete

view : Model -> Html.Html Msg
view m =
  let (w, h) = Util.windowSize ()
      grid = Html.div
               [ Attrs.id "grid"
               , Events.on "mousedown" (decodeClickEvent RecordClick)
               ]
               [ viewError m.error
               , Svg.svg
                 [ SA.width "100%"
                 , SA.height (toString h) ]
                 (viewCanvas m)
               ]
 in
    grid

viewError : Maybe String -> Html.Html Msg
viewError mMsg =
  let special =
    [ Html.a
        [ Events.onClick AddRandom , Attrs.src ""]
        [ Html.text "random" ]
      , Html.a
        [ Events.onClick ClearGraph , Attrs.src ""]
        [ Html.text "clear" ]
    ]
  in
  case mMsg of
    Just msg ->
      Html.div [Attrs.id "darkErrors"] (special ++ [Html.text msg])
    Nothing ->
      Html.div [] special



viewCanvas : Model -> List (Svg.Svg Msg)
viewCanvas m =
    let visible = List.filter .visible (G.orderedNodes m)
        nodes = List.indexedMap (\i n -> viewNode m n i) visible
        values = visible |> List.map (viewValue m) |> List.concat
        edges = visible |> List.map (viewNodeEdges m) |> List.concat
        entry = viewEntry m
        yaxis = svgLine m {x=0, y=2000} {x=0,y=-2000} "" "" [SA.strokeWidth "1px", SA.stroke "#777"]
        xaxis = svgLine m {x=2000, y=0} {x=-2000,y=0} "" "" [SA.strokeWidth "1px", SA.stroke "#777"]
        allSvgs = xaxis :: yaxis :: (edges ++ values ++ nodes ++ entry)
    in allSvgs

placeHtml : Model -> Pos -> Html.Html Msg -> Svg.Svg Msg
placeHtml m pos html =
  let rcpos = Viewport.toViewport m pos in
  Svg.foreignObject
    [ SA.x (toString rcpos.vx)
    , SA.y (toString rcpos.vy)
    ]
    [ html ]

viewEntry : Model -> List (Svg.Svg Msg)
viewEntry m =
  let autocompleteList =
        (List.indexedMap
           (\i item ->
              let highlighted = m.complete.index == i
                  hlClass = if highlighted then " highlighted" else ""
                  class = "autocomplete-item" ++ hlClass
                  str = Autocomplete.asName item
                  name = Html.span [] [Html.text str]
                  types = Html.span
                    [Attrs.class "types"]
                    [Html.text <| Autocomplete.asTypeString item ]
              in Html.li
                [ Attrs.class class ]
                [name, types])
           m.complete.completions)

      autocompletions = case (m.state, m.complete.index) of
                          (Entering _ (Filling _ (ParamHole _ _ _)), -1) ->
                            [ Html.li
                              [ Attrs.class "autocomplete-item greyed" ]
                              [ Html.text "Press down to autocomplete…" ]
                            ]
                          _ -> autocompleteList


      autocomplete = Html.ul
                     [ Attrs.id "autocomplete-holder" ]
                     autocompletions


      -- two overlapping input boxes, one to provide suggestions, one
      -- to provide the search
      (indent, suggestion, search) =
        Autocomplete.compareSuggestionWithActual m.complete m.complete.value

      indentHtml = "<span style=\"font-family:sans-serif; font-size:14px;\">" ++ indent ++ "</span>"
      (width, _) = Util.htmlSize indentHtml
      w = width |> toString
      searchInput = Html.input [ Attrs.id Defaults.entryID
                               , Events.onInput EntryInputMsg
                               , Attrs.style [("text-indent", w ++ "px")]
                               , Attrs.value search
                               , Attrs.spellcheck False
                               , Attrs.autocomplete False
                               ] []
      suggestionInput = Html.input [ Attrs.id "suggestion"
                                   , Attrs.disabled True
                                   , Attrs.value suggestion
                                   ] []

      input = Html.div
              [Attrs.id "search-container"]
              [searchInput, suggestionInput]

      viewForm = Html.form
                 [ Events.onSubmit (EntrySubmitMsg) ]
                 [ input, autocomplete ]

      paramInfo =
        case m.state of
          Entering _ (Filling _ (ParamHole _ param _)) ->
            Html.div [] [ Html.text (param.name ++ " : " ++ param.tipe)
                        , Html.br [] []
                        , Html.text param.description
                        ]
          _ -> Html.div [] []

      -- outer node wrapper
      classes = "selection function node entry"

      wrapper = Html.div
                [ Attrs.class classes
                , Attrs.width 100]
                [ paramInfo, viewForm ]
      html pos = placeHtml m pos wrapper
  in
    case m.state of
      Entering _ (Filling n h) ->
        let holePos = holeDisplayPos m h
            edgePos = { x = holePos.x + 10
                      , y = holePos.y + 10}
            nodePos = { x = n.pos.x + 10
                      , y = n.pos.y + 10}
        in
        [svgLine m nodePos edgePos "" "" edgeStyle, html holePos]
      Entering _ (Creating pos) -> [html pos]
      _ -> []


valueDisplayPos : Model -> Node -> Pos
valueDisplayPos m n =
  if (G.outgoingNodes m n |> List.length |> (==) 1) && G.hasAnonParam m n.id
  then Entry.holeCreatePos m (ResultHole n)
  else
    let xpad = max (G.nodeWidth n + 50) 250
    in {x=n.pos.x+xpad, y=n.pos.y}

holeDisplayPos : Model -> Hole -> Pos
holeDisplayPos m hole =
  case hole of
    ResultHole _ -> let {x,y} = Entry.holeCreatePos m hole
                    in {x=x, y=y + 50}
    ParamHole n _ _ -> {x=n.pos.x-350, y=n.pos.y-100}



viewValue : Model -> Node -> List (Html.Html Msg)
viewValue m n =
  let valueStr val tipe =
        val
          |> String.trim
          |> String.left 120
          |> Util.replace "\n" ""
          |> Util.replace "\r" ""
          |> Util.replace "\\s+" " "
          |> (\s -> if String.length s > 54
                    then String.left 54 s ++ "…" ++ String.right 1 (String.trim val)
                    else s)
          |> \v -> v ++ " :: " ++ tipe
          |> Html.text
      -- lv = case Dict.get (n.id |> deID) m.phantoms of
      --   Nothing -> n.liveValue
      --   Just pn -> pn.liveValue
      lv = n.liveValue
      isPhantom = lv /= n.liveValue
      class = if isPhantom then "phantom" else "preview"
      newPos = valueDisplayPos m n
      displayedBelow = newPos.y /= n.pos.y
      edge =
        if displayedBelow
        then [svgLine m {x=n.pos.x + 10, y=n.pos.y+10} {x=newPos.x+10,y=newPos.y+10} "" "" edgeStyle]
        else []
  in
  edge ++
  [placeHtml m newPos
      (case lv.exc of
        Nothing -> Html.pre
                    [Attrs.class class, Attrs.title lv.value]
                    [valueStr lv.value lv.tipe]
        Just exc -> Html.span
                      [ Attrs.class <| "unexpected " ++ class
                      , Attrs.title
                          ( "Problem: " ++ exc.short
                          ++ "\n\nActual value: " ++ exc.actual
                          ++ "\n\nExpected: " ++ exc.expected
                          ++ "\n\nMore info: " ++ exc.long
                        ) ]
                      [ Html.pre
                        [ ]
                        [ valueStr exc.result exc.resultType ]
                      , Html.span
                          [Attrs.class "info" ]
                          [Html.text "ⓘ "]
                      , Html.span
                          [Attrs.class "explanation" ]
                          [Html.text exc.short ]])]


viewNode : Model -> Node -> Int -> Html.Html Msg
viewNode m n i =
  case n.tipe of
    Arg -> viewNormalNode m n i
    FunctionDef -> Html.div [] []
    _ -> viewNormalNode m n i

-- TODO: If there are default parameters, show them inline in
-- the node body
viewNormalNode : Model -> Node -> Int -> Html.Html Msg
viewNormalNode m n i =
  let
      -- header
      header = [ Html.span
                   [Attrs.class "letter"]
                   [Html.text (G.int2letter i)]
               ]

      -- heading
      params = G.args n
              |> List.map
                    (\(p, a) ->
                      if p.tipe == "Function"
                      then ("", "")
                      else
                        case (a, p) of
                          (Const c, _) -> ("arg_const", if c == "null" then "∅" else c)
                          (NoArg, _) -> ("arg_none", "◉")
                          (Edge _, _) -> ("arg_edge", "◉"))
               |> List.map (\(class, val) ->
                              Html.span
                                [ Attrs.class class]
                                [ Html.text <| " " ++ val])

      heading = Html.span
                [ Attrs.class "title"]
                ((Html.span [Attrs.class "name"] [Html.text n.name]) :: params)


      -- fields (in list)
      viewField (name, tipe) = [ Html.text (name ++ " : " ++ tipe)
                               , Html.br [] []]
      viewFields = List.map viewField n.fields

      -- list
      list = if viewFields /= []
             then
               [Html.span
                 [Attrs.class "list"]
                 (List.concat viewFields)]
             else []

  in
    placeNode
      m
      n
      (G.nodeWidth n)
      []
      []
      header
      (heading :: list)

placeNode : Model -> Node -> Int -> List (Html.Attribute Msg) -> List String -> List (Html.Html Msg) -> List (Html.Html Msg) -> Html.Html Msg
placeNode m n width attrs classes header body =
  let width_attr = Attrs.style [("width", (toString width) ++ "px")]
      selectedCl = if Selection.isSelected m n then ["selected"] else []
      class = String.toLower (toString n.tipe)
      classStr = String.join " " (["node", class] ++ selectedCl ++ classes)
      node = Html.div
                (width_attr :: (Attrs.class classStr) :: attrs)
                body
      header_wrapper = Html.div [Attrs.class "header", width_attr ] header
      wrapper = Html.div [] [ node, header_wrapper ]
  in
    placeHtml m n.pos wrapper

edgeStyle : List (Svg.Attribute Msg)
edgeStyle =
  [ SA.strokeWidth Defaults.edgeSize
  , SA.stroke Defaults.edgeStrokeColor
  ]

viewNodeEdges : Model -> Node -> List (Svg.Svg Msg)
viewNodeEdges m n =
  n
    |> G.incomingNodePairs m
    |> List.filter (\(n, p) -> n.tipe /= FunctionDef)
    |> List.map (\(n2, p) -> viewEdge m n2 n p)

viewEdge : Model -> Node -> Node -> ParamName -> Svg.Svg Msg
viewEdge m source target param =
    let targetPos = target.pos
        (sourceW, sourceH) = G.nodeSize source
        (targetW, targetH) = G.nodeSize target
        spos = { x = source.pos.x + 10
               , y = source.pos.y + (sourceH // 2)}
        tpos = { x = target.pos.x + 10
               , y = target.pos.y + (targetH // 2)}
    in svgLine
      m
      spos
      tpos
      (toString source.id)
      (toString target.id)
      edgeStyle

svgLine : Model -> Pos -> Pos -> String -> String -> List (Svg.Attribute Msg) -> Svg.Svg Msg
svgLine m p1a p2a sourcedebug targetdebug attrs =
  let p1v = Viewport.toViewport m p1a
      p2v = Viewport.toViewport m p2a
  in
  Svg.line
    ([ SA.x1 (toString p1v.vx)
     , SA.y1 (toString p1v.vy)
     , SA.x2 (toString p2v.vx)
     , SA.y2 (toString p2v.vy)
     , VirtualDom.attribute "source" sourcedebug
     , VirtualDom.attribute "target" targetdebug
     ] ++ attrs)
    []

decodeClickEvent : (MouseEvent -> a) -> JSD.Decoder a
decodeClickEvent fn =
  let toA : Int -> Int -> Int -> a
      toA px py button =
        fn {pos= {vx=px, vy=py}, button = button}
  in JSDP.decode toA
      |> JSDP.required "pageX" JSD.int
      |> JSDP.required "pageY" JSD.int
      |> JSDP.required "button" JSD.int

