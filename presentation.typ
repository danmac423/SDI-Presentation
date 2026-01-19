#import "@preview/touying:0.6.1": *
#import themes.university: *
#import "@preview/numbly:0.1.0": numbly
#import "@preview/lovelace:0.3.0": *
#import "@preview/theorion:0.3.2": *
#import cosmos.clouds: *

#show: show-theorion



#show: university-theme.with(
  aspect-ratio: "16-9",
  // align: horizon,
  config-info(
    title: [
      #set par(leading: 0.3em)
      Modele dyfuzyjne w zadaniu super-rozdzielczości wideo na konsumenckich kartach graficznych],
    author: [ Daniel Machniak],
    authors: [
      #text("Daniel Machniak", size: 27pt)\
      promotor: prof. dr hab. inż. Przemysław Rokita

    ],
    date: datetime.today(),
    institution: [Instytut Informatyki],
    faculty: [Wydzial ],
  ),
  config-colors(
    primary: rgb("#04364A"),
    ary: rgb("#176B87"),
    tertiary: rgb("#448C95"),
    neutral-lightest: rgb("#fafafa"),
    neutral-darkest: rgb("#0a0a0a"),
  ),
  config-common(new-section-slide-fn: new-section-slide.with(numbered: false)),
  header-right: "",
)

#set text(lang: "pl")
#show outline.entry: it => link(it.element.location(), it.indented(
  it.prefix(),
  it.body(),
))

#set heading(numbering: numbly("{1:1.}", (..) => h(-0.3em)))


#set math.equation(numbering: "(1)")
#show ref: it => {
  let eq = math.equation
  let el = it.element
  if el != none and el.func() == eq {
    // Override equation references.
    numbering(
      el.numbering,
      ..counter(eq).at(el.location()),
    )
  } else {
    // Other references as usual.
    it
  }
}

#show figure.caption: set text(size: 18pt)


#title-slide()

== Plan prezentacji
#set align(horizon)
#set par(leading: 1.5em)

+ Cel pracy
+ Wprowadzenie do problematyki VSR
+ Podstawy teoretyczne: Transformery i Dyfuzja
+ Analiza architektury FlashVSR
+ Optymalizacja i implementacja
+ Ewaluacja i podsumowanie

// == Plan prezentacji
// #align(horizon)[
//   #set par(leading: 1em)
//   #components.adaptive-columns(outline(
//     target: heading.where(level: 1),
//     title: none,
//     indent: 1em,
//   )) <touying:hidden>
// ]

// = Cel pracy

== Cel pracy

#align(horizon)[
  #set par(justify: true)
  #set par(leading: 1em)
  Celem pracy jest opracowanie potoku przetwarzania w zadaniu super-rozdzielczości wideo (VSR) z wykorzystaniem modeli dyfuzyjnych na kartach graficznych klasy konsumenckiej. Istotnym elementem pracy jest także zbadanie wpływu technik optymalizacji na jakość rekonstruowanych materiałów.
]




= Wprowadzenie do problematyki VSR

== Sformułowanie zadania super-rozdzielczości wideo...

#align(horizon)[
  #set par(justify: true)
  #set par(leading: 1em)
  Zadanie super-rozdzielczości wideo (ang. _video super-resolution_, *VSR*) to proces rekonstrukcji sekwencji wideo o wysokiej rozdzielczości (HR) na podstawie materiału wejściowego o niskiej rozdzielczości (LR), wykorzystujący przestrzenno-czasowe zależności między sąsiednimi klatkami do odzyskania brakujących szczegółów @liu22.
]

== Sformułowanie zadania super-rozdzielczości wideo...

#align(horizon)[
  // #set par(leading: 1em)
  Proces degradacji klatek HR można formalnie zapisać jako:

  $
    I_i = phi.alt(hat(I)_i, {hat(I)_j}^(i+N)_(j=i-N)\;theta_(alpha)),
  $<degradation_eq>

  - $I$ - klatki LR,
  - $hat(I)$ - klatki HR,
  - $phi.alt$ - funkcja degradacji,
  - $theta_(alpha)$ - czynniki degradacji (szum, rozmycie, kompresja).
]

== Sformułowanie zadania super-rozdzielczości wideo...

#align(horizon)[
  // #set par(leading: 1em)
  VSR można zatem zdefiniować jako proces odwrotny równania @degradation_eq i opisać wzorem:

  $
    hat(I)_("SR"_i) = f_("VSR")(I_i, {I_j}^(i+N)_(j=i-N)\;theta_(f_("VSR"))),
  $<vsr_eq>

  - $hat(I)_("SR")$ - zrekonstruowane klatki HR,
  - $I$ - klatki LR,
  - $f_("VSR")$ - model super-rozdzielczości,
  - $theta_(f_("VSR"))$ - uczone parametry modelu.
]

== Sformułowanie zadania super-rozdzielczości wideo
#align(horizon)[#figure(
  image("assets/vsr.png", width: 90%),
  caption: [Schemat zadania super-rozdzielczości wideo (VSR).
    //  Model VSR rekonstruuje klatkę wysokiej rozdzielczości $hat(I)_("SR"_i)$ na podstawie sekwencji klatek niskiej rozdzielczości ${I_j}^(i+N)_(j=i-N)$.
  ],
)]

== Kluczowe wyzwania w VSR

#align(horizon)[
  #set par(justify: true)

  + *Rekonstrukcja szczegółów:*
    Zadaniem modelu jest odtworzenie realistycznych tekstur i krawędzi, które zostały bezpowrotnie utracone w procesie obniżania rozdzielczości.

  + *Wykorzystanie zależności czasowych:*
    Algorytm musi efektywnie pobierać brakujące informacje z klatek sąsiednich.

  + *Zapewnienie spójności wideo:*
    Kluczowym wymogiem jest zachowanie stabilności obrazu w czasie, aby uniknąć nienaturalnego migotania pomiędzy kolejnymi klatkami sekwencji.
]

== Reprezentacja danych

#align(horizon)[
  W widzeniu komputerowym sekwencja wideo reprezentowana jest jako tensor 4-wymiarowy:

  $
    I in RR^(N times C times H times W)
  $

  #grid(columns: (70%, 30%))[
    Gdzie wymiary oznaczają kolejno:
    - $N$: Liczba klatek,
    - $C$: Kanały kolorów (zazwyczaj 3 dla RGB),
    - $H$, $W$: Wysokość i szerokość (rozdzielczość).
  ][
    #image("assets/video_tensor.png")
  ]
]

== Wyzwanie obliczeniowe

#align(horizon)[
  Przetwarzanie wideo wiąże się z rzędem wielkości większym zużyciem pamięci niż w przypadku obrazów statycznych.

  _Przykład:_ Tylko *1 sekunda* wideo 4K UHD (30 FPS, float16) zajmuje w pamięci:
  $ 30 dot 3840 dot 2160 dot 3 dot 2 "bajty" approx 1.49 "GB" $

  #set par(justify: true)
  W przypadku modeli dyfuzyjnych, wysokie zapotrzebowanie na VRAM podczas inferencji wynika z konieczności alokacji pamięci dla wielowymiarowych map cech oraz macierzy atencji.
]

= Podstawy teoretyczne: Transformery i dyfuzja

== Vision Transformer...

#align(horizon)[
  #set par(justify: true)

  Tradycyjne sieci splotowe ograniczają się do *lokalnego pola recepcji*. Wprowadzenie architektury Transformer zmieniło ten paradygmat:

  #v(2em)

  + *Tokenizacja:*
    Obraz dzielony jest na sekwencję łat (ang. _patches_), które traktowane są analogicznie do słów w przetwarzaniu języka.
  // + *Globalny mechanizm uwagi:* Umożliwia modelowanie *długodystansowych zależności*. Każdy fragment obrazu może czerpać informacje z każdego innego, niezależnie od odległości w czasoprzestrzeni.

  // $ "Attention"(Q, K, V) = "softmax"((Q K^T) / sqrt(d_k)) V $

  // + *Problem złożoności:*
  //   Analiza globalna wiąże się ze *złożonością kwadratową* $O(N^2)$ względem liczby tokenów. Dla wideo wysokiej rozdzielczości (duże $N$) macierz atencji staje się wąskim gardłem pamięciowym.
]
== Vision Transformer...

#align(horizon)[
  #set par(justify: true)
  2. *Globalny mechanizm uwagi:* Umożliwia modelowanie *długodystansowych zależności*. Każdy fragment obrazu może czerpać informacje z każdego innego, niezależnie od odległości w czasoprzestrzeni.

  $ "Attention"(Q, K, V) = "softmax"((Q K^T) / sqrt(d_k)) V $

  3. *Problem złożoności:*
    Analiza globalna wiąże się ze *złożonością kwadratową* $O(N^2)$ względem liczby tokenów. Dla wideo wysokiej rozdzielczości macierz atencji staje się wąskim gardłem pamięciowym.
]

== Vision Transformer
#align(horizon)[#figure(
  image("assets/vit.png", width: 80%),
  caption: [Schemat architektury Vision Transformer (ViT) @dosovitskiy2021.
    // Obraz wejściowy dzielony jest na sekwencję łat (ang. patches) o stałym rozmiarze. Po liniowym rzutowaniu i dodaniu kodowania pozycyjnego, sekwencja wektorów trafia do standardowego enkodera Transformera.
  ],
)]

== Generatywne modele dyfuzyjne...

#align(horizon)[
  #set par(justify: true)

  Modele dyfuzyjne @ho2020denoisingdiffusionprobabilisticmodels to probabilistyczne modele generatywne, które uczą się tworzyć dane poprzez *iteracyjne odwracanie procesu degradacji*. Całość opiera się na dwóch łańcuchach Markowa:

  + *Proces zaszumiania\:*
    Polega na stopniowym, krokowym dodawaniu szumu Gaussa do obrazu wejściowego $x_0$. Po wykonaniu $T$ kroków, oryginalny obraz zamienia się w całkowity szum losowy.
    $ q(x_t | x_(t-1)) = cal(N)(x_t; sqrt(1 - beta_t) x_(t-1), beta_t I) $


]

== Generatywne modele dyfuzyjne
#align(horizon)[
  #set par(justify: true)
  2. *Proces odszumiania:*
    To właściwy proces generacji. Sieć neuronowa uczy się przewidywać stan $x_(t-1)$ na podstawie zaszumionego $x_t$.
    $ p_(theta)(x_(t-1) | x_t) = cal(N)(x_(t-1); mu_(theta)(x_t, t), Sigma_(theta)(x_t, t)) $

  #line(length: 100%, stroke: 0.5pt + gray)

  #figure(
    image("assets/diff_graph.png", width: 90%),
    caption: [
      Schemat działania modelu dyfuzyjnego @ho2020denoisingdiffusionprobabilisticmodels.
      // Proces generatywny $p_theta$ iteracyjnie rekonstruuje obraz $x_0$ z szumu $x_T$, odwracając proces degradacji $q$.
    ],
  )
]

== Architektura Diffusion Transformer...

#align(horizon)[
  #set par(justify: true)

  Peebles i Xie @peebles2023scalablediffusionmodelstransformers zaproponowali zastąpienie klasycznego U-Netu architekturą Transformera. Proces przetwarzania przebiega w trzech krokach:

  + *Tokenizacja:*
    Wejściowy zaszumiony tensor (*w przestrzeni ukrytej*) jest dzielony na sekwencję łat $x_p$.

  + *Bloki Transformera z mechanizmem adaLN:*
    Zamiast standardowej normalizacji, w DiT zastosowano *Adaptive Layer Norm (adaLN)*.
  // Parametry normalizacji (skala $gamma$ i przesunięcie $beta$) nie są stałe, lecz generowane dynamicznie na podstawie wektora czasu $t$ i warunku $c$.
  // $ "adaLN"(h, t, c) = gamma(t, c) dot "Norm"(h) + beta(t, c) $
  // _Co to oznacza?_ Sieć "wie", jak mocno modyfikować cechy w zależności od tego, czy jest to początek (duży szum), czy koniec procesu (detale).

  + *Projekcja końcowa i Reshape:*
    Przetworzony tensor przechodzi przez warstwę liniową, która rzutuje go do kształtu wejściowego.
]

== Architektura Diffusion Transformer...

#align(horizon)[#figure(
  image("assets/dit.png", width: 50%),
  caption: [Schemat architektury Diffusion Transformer (DiT).
    Po lewej: Globalny przepływ danych.
    // Zaszumiony tensor wejściowy jest dzielony na sekwencję łat , przetwarzany przez $N$ bloków transformera, a następnie rzutowany przez warstwę liniową i formowany w tensor wyjściowy.
    Po prawej: Szczegóły bloku DiT z mechanizmem adaLN-Zero.
    // Parametry normalizacji i skalowania ($gamma, beta, alpha$) są generowane dynamicznie przez sieć MLP na podstawie warunkowania (czas $t$, etykieta $y$),
  ],
)]

== Architektura Diffusion Transformer
#set par(justify: true)

W dotychczasowych modelach dyfuzyjnych standardem był splotowy \
U-Net. Zastąpienie go architekturą DiT wnosi kluczowe ulepszenia:
#align(horizon)[
  #set par(justify: true)


  #v(-1.5em)
  - *Skalowalność*,
  // W przeciwieństwie do U-Netów, gdzie zysk z dodawania parametrów jest nieoczywisty, DiT wykazuje silną korelację między mocą obliczeniową (Gflops) a jakością obrazu (FID). Większy model monotonicznie przekłada się na lepszy wynik.


  #v(1.5em)
  - *Globalne przetwarzanie kontekstu*,
  // U-Net opiera się na lokalnych splotach, co wymusza stosowanie głębokich struktur downsamplingu, aby "widzieć" cały obraz. DiT, dzięki mechanizmowi atencji, posiada globalne pole recepcji od pierwszej warstwy, eliminując potrzebę skomplikowanych hierarchii przestrzennych.

  #v(1.5em)
  - *Uproszczenie architektury.*
  // DiT usuwa specyficzne dla U-Netu "indukcyjne obciążenia" (ang. _inductive biases_), dowodząc, że specjalizowana architektura splotowa nie jest konieczna do osiągnięcia wyników State-of-the-Art.
]

= Analiza architektury\ FlashVSR

== FlashVSR...
#set par(justify: true)
FlashVSR @zhuang2025flashvsrrealtimediffusionbasedstreaming to model dyfuzyjny do VSR działający w trybie strumieniowym i generujący wynik w pojedynczym kroku.

#align(horizon)[
  #set par(justify: true)

  // Rozwiązuje on problem wysokich opóźnień (latency) typowych dla dyfuzji.

  #v(-1.5em)
  - *Wydajność SOTA:*
    Model osiąga prędkość *~17 FPS* dla rozdzielczości $768 times 1408$ na pojedynczym układzie A100.
  // Stanowi to nawet *12-krotne przyspieszenie* względem dotychczasowych modeli one-step.
  #v(1.5em)

  - *Generalizacja do ultra-wysokich rozdzielczości:*
    Dzięki unikalnej konstrukcji atencji, FlashVSR eliminuje błędy generalizacji przy skalowaniu do ultra-wysokich rozdzielczości.
]

== FlashVSR
#set par(justify: true)

Fundamentem FlashVSR jest trójetapowy proces destylacji wiedzy oraz architektura przystosowana do przetwarzania przyczynowego (causal).

#align(horizon)[
  #set par(justify: true)

  #v(-1em)

  - *Nauczyciel i Uczeń:*
    Wiedza z potężnego modelu nauczyciela jest destylowana do lekkiego modelu ucznia.
  // (Full-Attention Teacher) -> (Sparse-Causal Student)
  #v(1.5em)

  - *Przetwarzanie strumieniowe (KV Cache):*
    Model wykorzystuje mechanizm *KV Cache*, znany z dużych modeli językowych.
  // Pozwala to na przetwarzanie tokenów (causal processing) bez konieczności ponownego obliczania cech dla poprzednich tokenów, co drastycznie redukuje narzut obliczeniowy.
]


== Innowacje architektury FlashVSR

#align(horizon)[
  #set par(justify: true)
  #set list(indent: 1.5em)

  1. *Locality-Constrained Sparse Attention*
  // \ Rozwiązanie problemu artefaktów w 4K wynikających z periodyczności RoPE:
  - *Ograniczenie lokalne:* Wymuszenie atencji w lokalnym oknie eliminuje błędy pozycyjne i zapobiega "zawijaniu się" wzorców,
  - *Rzadka atencja:* Przetwarzanie jest wyłącznie *top-k* kluczowych obszarów.

  2. *Tiny Conditional Decoder*
  - *Warunkowanie klatką LR:* Bezpośrednie wykorzystanie klatki niskiej rozdzielczości jako sygnału pomocniczego upraszcza zadanie sieci.
]

= Optymalizacja\ i implementacja

== Implementacja potoku przetwarzania...

W celu uruchomienia modelu na kartach graficznych klasy konsumenckiej, potok przetwarzania wykorzystujący techniki kafelkowania:
#align(horizon)[
  #set par(justify: true)
  #v(-1em)


  1. *Kafelkowanie czasowe:*
    Sekwencja wideo jest przetwarzana sekwencyjnie w krótszych klipach.

  #v(1em)

  2. *Kafelkowanie przestrzenne:*
    Każda klatka dzielona jest na mniejsze fragmenty z uwzględnieniem marginesu.
]

== Implementacja potoku przetwarzania

#align(horizon)[#figure(
  image("assets/tiling.png", width: 60%),
  caption: [Przykład kafelkowania przestrzennego.
  ],
)]

== Optymalizacja mechanizmu atencji

#align(horizon)[
  #set par(justify: true)
  Istotną modyfikacją względem oryginalnej architektury była wymiana kerneli obliczeniowych atencji:

  #v(1em)
  #align(center)[
    #grid(
      columns: (40%, 10%, 40%),
      align: (center, center, center),
      [*Oryginał* \ Flash Attention \ + Block Sparse Attention],
      [$arrow.r$],
      [*Modyfikacja* \ Sage Attention \ + Sparge Attention],
    )
  ]
  #v(1em)

  + *Sage Attention:*
    Zastosowanie precyzyjnej kwantyzacji 8-bitowej (int8) w macierzach atencji..

  + *Sparge Attention:*
    Zoptymalizowany wariant rzadkiej atencji, redukujący złożoność obliczeniową dla tokenów o niskiej istotności.
]

= Ewaluacja\ i podsumowanie

== Wyniki eksperymentów

// Poniższa tabela przedstawia porównanie jakości rekonstrukcji dla trzech badanych konfiguracji. Dla metod wykorzystujących kafelkowanie przestrzenne przyjęto parametry: *rozmiar kafelka $192 times 192$* oraz *margines $24$ px*.


#show table: set text(size: 0.6em)
#show figure.where(kind: table): set figure.caption(position: top)
#show figure.caption: set text(size: 1em)


#v(2em)

#figure(
  table(
    columns: (auto, auto, 25%, 25%, 25%),
    inset: (x, y) => 4pt,
    align: (x, y) => if x < 2 { left + horizon } else { center + horizon },
    stroke: (x, y) => {
      let s = (top: 0pt, bottom: 0pt, left: 0pt, right: 0pt)

      if x == 2 { s.insert("left", 0.5pt) }
      if y == 0 { s.insert("top", 1pt) }
      if y == 1 { s.insert("top", 0.5pt) }
      if y == 1 { s.insert("top", 0.5pt) }
      if y == 8 { s.insert("top", 0.5pt) }
      if y == 8 { s.insert("bottom", 1pt) }
      if y == 11 { s.insert("bottom", 1pt) }

      return s
    },

    // --- Nagłówek ---
    [Zbiór danych], [Metryka], [FlashVSR], [FlashVSR + kafelkowanie], [FlashVSR + kafelkowanie + modyfikacja atencji],

    // --- REDS ---
    table.cell(rowspan: 7)[*REDS*],
    [PSNR$arrow.t$], [23.31], [23.16], [23.13],
    [SSIM$arrow.t$], [0.6110], [0.6075], [0.6068],
    [LPIPS$arrow.b$], [0.3866], [0.3950], [0.3962],
    [NIQE$arrow.b$], [3.489], [3.580], [3.595],
    [MUSIQ$arrow.t$], [66.63], [65.20], [65.05],
    [CLIPIQA$arrow.t$], [0.5221], [0.5160], [0.5152],
    [DOVER$arrow.t$], [12.66], [12.15], [12.08],

    // --- VideoLQ ---
    table.cell(rowspan: 4)[*VideoLQ*],
    [NIQE$arrow.b$], [4.070], [4.150], [4.165],
    [MUSIQ$arrow.t$], [52.27], [51.40], [51.28],
    [CLIPIQA$arrow.t$], [0.3601], [0.3540], [0.3532],
    [DOVER$arrow.t$], [7.481], [7.250], [7.210],
  ),
  caption: [Porównanie jakości rekonstrukcji dla trzech badanych konfiguracji. Dla metod wykorzystujących kafelkowanie przestrzenne przyjęto parametry: rozmiar kafelka $192 times 192$ oraz margines $24$ px.],
)

== Prezentacja efektów wizualnych

#align(center + horizon)[
  #set par(justify: true)

  Poniżej przedstawiono bezpośrednie porównanie sekwencji wejściowej  z wynikiem rekonstrukcji uzyskanym przez  model FlashVSR.

  #v(1em)

  #grid(
    columns: (1fr, 1fr),
    gutter: 2em,
    // Odstęp między gifami
    align: center,

    // Kolumna 1: LR
    figure(
      // Zmień nazwę pliku na swoją
      image("assets/example.gif", width: 70%),
      caption: [
        Wideo LR.
      ],
    ),

    // Kolumna 2: HR
    figure(
      // Zmień nazwę pliku na swoją
      image("assets/example.gif", width: 70%),
      caption: [
        Wideo HR (FlashVSR).
      ],
    ),
  )
]

== Plan prac

W ramach pracy przewidziałem realizację następujących etapów:
#align(horizon)[

  #v(-1.5em)
  1. *Analiza technik kwantyzacji:*
    // Zbadanie wpływu redukcji precyzji wag na jakość rekonstrukcji oraz szybkość inferencji. Porównanie dwóch strategii:
    - *PTQ (Post-Training Quantization):* Kwantyzacja wytrenowanego modelu.
    - *QAT (Quantization-Aware Training):* Integracja kwantyzacji podczas treningu modelu.
  #v(0.5em)

  2. *Implementacja aplikacji użytkowej:*
    Stworzenie aplikacji z graficznym interfejsem, który zintegruje opracowany potok przetwarzania.
]



== Bibliografia
#set text(size: 18pt)
#bibliography("references.bib", title: none, full: true)

