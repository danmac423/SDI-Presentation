#import "@local/fine-lncs:0.3.0": author, institute, lncs, proof, theorem

#let inst_wut = institute(
  "Politechnika Warszawska",
  addr: "plac Politechniki 1, 00-661 Warszawa, Polska",
)

#show: lncs.with(
  title: "Modele dyfuzyjne w zadaniu super-rozdzielczości wideo na konsumenckich kartach graficznych",
  title-running: none,
  authors: (
    author("Daniel Machniak", insts: (inst_wut)),
  ),
  abstract: [
    Adaptacja modeli dyfuzyjnych typu Diffusion Transformer (DiT) do zadania super-rozdzielczości wideo (VSR) wiąże się z wysokimi wymaganiami pamięciowymi, często uniemożliwiającymi inferencję na sprzęcie konsumenckim. Niniejszy artykuł prezentuje zoptymalizowany potok przetwarzania oparty na architekturze FlashVSR, umożliwiający efektywne uruchomienie modelu na kartach graficznych z 10 GB VRAM. Wdrożono strategię kafelkowania przestrzennego oraz zastąpiono standardowe mechanizmy uwagi wydajnymi wariantami: kwantyzowanym SageAttention oraz dynamicznie rzadkim SpargeAttention. Wyniki eksperymentów na zbiorach REDS i VideoLQ potwierdzają, że proponowane podejście skutecznie redukuje narzut pamięciowy przy marginalnym spadku wierności rekonstrukcji, czyniąc zaawansowane metody VSR bardziej dostępnymi.
  ],
  keywords: (
    "Super-rozdzielczość wideo",
    "Modele dyfuzyjne",
    "FlashVSR",
    "Transformery wizyjne",
    "Optymalizacja pamięciowa",
  ),
  bibliography: bibliography("refs.bib"),
  // optional configuration of page (takes all page parameter)
  // page_config: (paper: "a4")
)

= Wprowadzenie

Super-rozdzielczość wideo (ang. _Video Super-Resolution_, VSR) stanowi kluczowe zagadnienie w dziedzinie niskopoziomowego widzenia komputerowego, którego celem jest rekonstrukcja sekwencji wideo o wysokiej rozdzielczości (HR) z materiałów wejściowych o niskiej rozdzielczości (LR) @baniya24. W przeciwieństwie do super-rozdzielczości pojedynczego obrazu (SISR), zadanie to wymaga efektywnego wykorzystania korelacji czasowych oraz informacji zawartych w sąsiednich klatkach w celu odzyskania brakujących detali i zachowania spójności czasowej @baniya24.

#figure(
  image("../../assets/vsr.png", width: 80%),
  caption: [Ogólny schemat procesu super-rozdzielczości wideo (VSR). Model rekonstruuje klatkę wysokiej rozdzielczości na podstawie sekwencji klatek wejściowych.],
) <fig:vsr>

Dynamiczny rozwój głębokiego uczenia (ang. Deep Learning) w ostatniej dekadzie doprowadził do powstania zaawansowanych architektur, początkowo opartych na konwolucyjnych sieciach neuronowych (CNN), a następnie na Transformerach, które zdominowały zadania przetwarzania sekwencji @dosovitskiy2021@baniya24.

W ostatnich latach szczególną uwagę badaczy przyciągają probabilistyczne modele dyfuzyjne (ang. _Denoising Diffusion Probabilistic Models_, DDPM), które dzięki iteracyjnemu procesowi odszumiania pozwalają na generowanie próbek o jakości przewyższającej tradycyjne podejścia, takie jak GAN czy VAE @ho2020denoisingdiffusionprobabilisticmodels. Ewolucja tych systemów doprowadziła do powstania architektury Diffusion Transformer (DiT), która zastępuje tradycyjny szkielet U-Net mechanizmem uwagi, oferując lepszą skalowalność i efektywność w zadaniach generatywnych @peebles2023scalablediffusionmodelstransformers. Jednakże adaptacja modeli DiT do zadania VSR wiąże się z istotnymi wyzwaniami obliczeniowymi. Mechanizm uwagi charakteryzuje się kwadratową złożonością czasową i pamięciową $O(N^2)$ względem długości sekwencji wejściowej. W kontekście wideo, gdzie sekwencja tokenów obejmuje wymiary przestrzenne i czasowe, prowadzi to do zaporowego zapotrzebowania na pamięć GPU, co często uniemożliwia inferencję na sprzęcie konsumenckim.

Niniejszy artykuł podejmuje problem optymalizacji dyfuzyjnych modeli VSR w celu ich efektywnego uruchomienia na kartach graficznych o ograniczonej pamięci VRAM. Głównym celem pracy jest implementacja potoku przetwarzania opartego na architekturze FlashVSR, zintegrowanego z technikami redukcji narzutu pamięciowego. W szczególności badano zastosowanie kafelkowania przestrzenno-czasowego oraz nowoczesnych algorytmów uwagi, takich jak FlashAttention @dao2022flashattentionfastmemoryefficientexact oraz kwantyzowane SageAttention @zhang2025sageattentionaccurate8bitattention. Podejście to ma na celu przełamanie bariery sprzętowej przy zachowaniu wysokiej wierności rekonstrukcji obrazu.

= Tło teoretyczne i przegląd literatury

Historycznie metody VSR ewoluowały od prostych algorytmów interpolacyjnych do złożonych systemów sztucznej inteligencji. Wczesne podejścia oparte na głębokim uczeniu wykorzystywały dwuwymiarowe splotowe sieci neuronowe (2D CNN), które traktowały wideo jako zbiór niezależnych obrazów lub wykorzystywały proste mechanizmy fuzji czasowej. Przełomem okazało się wprowadzenie dedykowanych modułów do wyrównywania klatek, takich jak deformowalne sploty (Deformable Convolution) zastosowane w modelu EDVR, czy mechanizmy propagacji rekurencyjnej w BasicVSR. Rozwiązania te, choć skuteczne, często borykają się z ograniczeniami w modelowaniu długodystansowych zależności czasowych @liu22.

Równolegle, sukces architektury Transformer w przetwarzaniu języka naturalnego zainspirował jej adaptację do zadań wizyjnych. Transformer wizyjny (ang. _Vision Transformer_, ViT) @dosovitskiy2021 zastąpił lokalne operacje splotowe globalnym mechanizmem uwagi, co pozwoliło na lepsze uchwycenie kontekstu globalnego obrazu. W kontekście generatywnym, modele dyfuzyjne (DDPM) zdetronizowały sieci GAN, oferując stabilniejszy trening i wyższą jakość generowanych próbek. Połączenie tych dwóch nurtów doprowadziło do powstania architektury Diffusion Transformer (DiT) @peebles2023scalablediffusionmodelstransformers, która skaluje się efektywniej niż modele dyfuzyjne oparte na sieci U-Net. Niniejsza praca osadzona jest w tym najnowszym nurcie, adaptując architekturę DiT do zadania VSR przy jednoczesnym rozwiązaniu problemów wydajnościowych.

== Sformuowanie problemu VSR

Problem super-rozdzielczości wideo jest zdefiniowany jako zadanie odwrotne, w którym dążymy do odzyskania sekwencji wysokiej rozdzielczości (HR) na podstawie obserwowanej sekwencji o niskiej rozdzielczości (LR). Proces powstawania materiału LR jest zazwyczaj modelowany jako złożenie degradacji fizycznych i cyfrowych.

Ogólny model degradacji dla i-tej klatki wideo można zapisać jako funkcję zależną od klatki docelowej $hat(I)_i$ oraz jej sąsiedztwa czasowego @liu22:

$
  I_i = phi.alt(hat(I)_i, {hat(I)_j}^(i+N)_(j=i-N)\;theta_(alpha)),
$<degradation_eq>

gdzie $I_i$ oznacza obserwowaną klatkę o niskiej rozdzielczości, $hat(I)_i$ to sekwencja oryginalna o wysokiej rozdzielczości, N oznacza promień czasowy (zakres sąsiednich klatek), a $theta_(alpha)$ reprezentuje parametry procesu degradacji (np. szum, rozmycie).

W bardziej szczegółowym ujęciu, uwzględniającym ruch między klatkami oraz standardowe operacje przetwarzania sygnału, proces degradacji dla sąsiedniej klatki $j$ względem klatki referencyjnej $i$ jest definiowany jako @liu22:

$
  I_j = D B E_(i->j)hat(I)_i + n_j,
$<degradation_eq_dbe>

gdzie $D$ oznacza operator podpróbkowania (downsampling), $B$ reprezentuje operator rozmycia (blur), a $n_j$ to addytywny szum. Kluczowym elementem w kontekście wideo jest operator $E_(i -> j)$, który oznacza operację zniekształcenia (warping) zgodną z ruchem od klatki $i$ do $j$.

#figure(
  image("../../assets/degradation.png", width: 100%),
  caption: [Ilustracja modelu degradacji. Klatka HR podlega przekształceniom geometrycznym, rozmyciu, podpróbkowaniu i zaszumieniu, tworząc klatkę LR.],
) <fig:degradation>

Model ten zakłada, że klatka LR powstaje poprzez przekształcenie geometryczne klatki HR, jej rozmycie, zmniejszenie rozdzielczości oraz dodanie szumu.

Celem modelu VSR jest znalezienie funkcji odwzorowującej $f_("VSR")$, sparametryzowanej przez wagi $theta_(f_("VSR"))$, która estymuje klatkę wysokiej rozdzielczości $hat(I)_("SR"_i)$ na podstawie sekwencji klatek wejściowych LR @liu22:

$
  hat(I)_("SR"_i) = f_("VSR")(I_i, {I_j}^(i+N)_(j=i-N)\;theta_(f_("VSR"))),
$<vsr_eq>

== Transformer wizyjny (ViT)

Architektura Transformer, która stała się standardem w przetwarzaniu języka naturalnego, znalazła skuteczne zastosowanie w wizji komputerowej pod postacią Tranformera wizyjnego (ang. _Vision Transformer_, ViT). W przeciwieństwie do splotowych sieci neuronowych (CNN), które polegają na lokalnych operacjach splotu i wbudowanych założeniach indukcyjnych dotyczących lokalności i niezmienniczości przesunięcia, ViT interpretuje obraz jako sekwencję łat (ang. patches), przetwarzając je za pomocą standardowego enkodera Transformer @dosovitskiy2021.

#figure(
  image("../../assets/vit_pl.png", width: 90%),
  caption: [Schemat działania Transformera wizyjnego (ViT). Obraz dzielony jest na łaty, rzutowany liniowo i przetwarzany przez warstwy atencji.],
) <fig:vit>

W modelu ViT obraz wejściowy $x in RR^(H times W times C)$ jest dzielony na sekwencję spłaszczonych łat 2D $x in RR^(N times (P^2 dot.c C))$, gdzie $(P,P)$ to rozdzielczość pojedynczej łaty, a $N=H W\/ P^2$ stanowi efektywną długość sekwencji wejściowej. Każda łata jest następnie rzutowana liniowo do stałego wymiaru ukrytego $D$, a do uzyskanych wektorów dodawane są wyuczalne zanurzenia pozycyjne, aby zachować informację o strukturze przestrzennej obrazu. Tak przygotowana sekwencja tokenów jest przetwarzana przez warstwy wielogłowicowej uwagi (ang. _Multi-Head Self-Attention_, MSA), co pozwala modelowi na integrację informacji z całego obrazu już w pierwszych warstwach sieci, w przeciwieństwie do ograniczonego pola recepcyjnego w CNN @dosovitskiy2021.

Bezpośrednia adaptacja mechanizmu MSA do materiałów wideo wiąże się z opisanym we wstępie problemem eksplozji liczby tokenów $N$. Ponieważ sekwencja obejmuje wymiar czasowy, standardowa macierz uwagi staje się wąskim gardłem, co motywuje poszukiwanie wariantów atencji o zredukowanej złożoności lub zastosowanie technik okienkowych.

== Modele dyfuzyjne i architektura Diffusion Transformer (DiT)

Probabilistyczne modele dyfuzyjne odszumiania (DDPM) zrewolucjonizowały dziedzinę syntezy obrazów, oferując wyższą jakość generowanych próbek i większą różnorodność w porównaniu do wcześniejszych architektur GAN @peebles2023scalablediffusionmodelstransformers. Działanie tych modeli opiera się na dwóch procesach: ustalonym procesie "w przód", który stopniowo dodaje szum Gaussa do danych aż do uzyskania czystego szumu, oraz wyuczalnym procesie "wstecz", który iteracyjnie odtwarza strukturę danych z szumu, modelując rozkład warunkowy $p_(theta)(x_(t-1)divides x_(t))$ @ho2020denoisingdiffusionprobabilisticmodels.

#figure(
  image("../../assets/diff_graph.png", width: 80%),
  caption: [Graf probabilistyczny modelu dyfuzyjnego. Proces w przód ($q$) degraduje obraz do szumu, a proces wsteczny ($p_theta$) rekonstruuje obraz.],
) <fig:diff_graph>

Tradycyjnie, jako szkielet (ang. _backbone_) dla procesu odszumiania wykorzystywano architekturę U-Net opartą na splotach.

Ostatnie badania, w tym praca Peeblesa i Xie @peebles2023scalablediffusionmodelstransformers, zaproponowały nową klasę modeli określaną jako Diffusion Transformers (DiT), która zastępuje tradycyjny U-Net architekturą Transformera działającą na reprezentacji utajonej (ang. _latent space_). W podejściu tym obraz wejściowy zakodowany przez autoenkoder wariacyjny (ang. _variational autoencoder_, VAE) jest dzielony na sekwencję łat, analogicznie jak w modelu ViT, a następnie przetwarzany przez standardowe bloki transformera.

#figure(
  image("../../assets/dit_pl.png", width: 75%),
  caption: [Architektura DiT (po lewej) oraz szczegółowa budowa bloku DiT z mechanizmem adaLN-Zero (po prawej), sterującym procesem generacji na podstawie kroku czasowego $t$ i warunku $y$.],
) <fig:dit>

Kluczowym elementem adaptacji Transformera do zadań generatywnych jest mechanizm warunkowania. W architekturze DiT zastosowano warstwę Adaptive Layer Normalization (adaLN), która wykorzystuje parametry skali i przesunięcia w warstwach normalizacyjnych na podstawie wektorów osadzenia czasu (ang. _timestep_) i warunku (np. etykiety klasy lub obrazu LR).

Główną zaletą architektury DiT jest jej przewidywalna skalowalność. Autorzy wykazali silną korelację między złożonością obliczeniową modelu, a jakością generowanych obrazów - zwiększanie głębokości lub szerokości sieci prowadzi do systematycznej poprawy wyników, co czyni DiT atrakcyjnym wyborem dla zadań wymagających wysokiej wierności, takich jak VSR.

= Proponowana metoda i optymalizacja

W niniejszym rozdziale przedstawiono proponowane podejście do optymalizacji inferencji modeli super-rozdzielczości wideo na sprzęcie o ograniczonych zasobach pamięciowych. Opracowany potok przetwarzania integruje model FlashVSR z implementacją mechanizmów zarządzania pamięcią oraz zoptymalizowanymi jądrami obliczeniowymi atencji. Głównym założeniem jest redukcja narzutu pamięci VRAM poprzez dekompozycję problemu w wymiarze przestrzennym (kafelkowanie) oraz redukcję precyzji obliczeń w warstwach atencji, przy jednoczesnym zachowaniu spójności generowanej struktury obrazu.

== Bazowa architektura FlashVSR

Jako fundament proponowanego rozwiązania przyjęto architekturę FlashVSR @zhuang2025flashvsrrealtimediffusionbasedstreaming, która stanowi nowatorskie podejście do zagadnienia super-rozdzielczości wideo w trybie strumieniowym. W przeciwieństwie do standardowych modeli dyfuzyjnych, wymagających kosztownego obliczeniowo i wieloetapowego procesu odszumiania, FlashVSR wykorzystuje zaawansowany, trójetapowy proces destylacji wiedzy. Pozwala to na inferencję w pojedynczym kroku, w którym model ucznia mapuje szum w przestrzeni ukrytej bezpośrednio do czystego obrazu, co jest kluczowe dla zastosowań w czasie rzeczywistym.

Istotnym elementem architektury, zapewniającym efektywność w przetwarzaniu sekwencji wideo, jest adaptacja mechanizmu atencji do przetwarzania przyczynowego (ang. _causal processing_). W tym podejściu generacja bieżącej klatki zależy wyłącznie od informacji zawartych w klatkach poprzednich, co umożliwia zastosowanie mechanizmu buforowania kluczy i wartości (KV Cache), techniki zapożyczonej z dużych modeli językowych. Dzięki temu cechy wyekstrahowane z poprzednich kroków czasowych są przechowywane w pamięci VRAM, eliminując konieczność ich ponownego obliczania i drastycznie redukując liczbę operacji w potoku przetwarzania wideo.

Kolejnym wyróżnikiem modelu jest zastosowanie lokalnie ograniczonej rzadkiej atencji (ang. _Locality-Constrained Sparse Attention_). Standardowe mechanizmy atencji globalnej często wykazują trudności z generalizacją do rozdzielczości wyższych niż te wykorzystane w procesie treningowym, co objawia się artefaktami w postaci powtarzających się wzorców geometrycznych. FlashVSR rozwiązuje ten problem poprzez nałożenie maski rzadkości, która ogranicza pole recepcyjne każdego tokenu do lokalnego sąsiedztwa przestrzenno-czasowego. Podejście to nie tylko poprawia jakość rekonstrukcji na ultra-wysokich rozdzielczościach poprzez eliminację błędów pozycyjnych, ale także znacząco zmniejsza złożoność obliczeniową operacji mnożenia macierzy.

Uzupełnieniem architektury jest zoptymalizowany moduł dekodujący, określany jako Tiny Conditional Decoder. W tradycyjnych architekturach opartych na dyfuzji, dekoder wariacyjnego autoenkodera często stanowi wąskie gardło wydajnościowe. FlashVSR zastępuje go lekkim wariantem warunkowym, który oprócz reprezentacji utajonej przyjmuje jako wejście również przeskalowaną klatkę niskiej rozdzielczości. Wykorzystanie informacji strukturalnych bezpośrednio z obrazu wejściowego jako sygnału pomocniczego pozwala na znaczne odciążenie sieci dekodującej i redukcję jej głębokości, przy jednoczesnym zachowaniu wysokiej wierności detali.

== Strategia kafelkowania przestrzenno-czasowego

W celu przezwyciężenia ograniczeń pamięci VRAM, uniemożliwiających przetwarzanie całego wideo wysokiej rozdzielczości, zastosowano dekompozycję danych. W domenie czasowej długa sekwencja dzielona jest na nakładające się klipy, które są przetwarzane niezależnie, a ich spójność na granicach zapewnia uśrednianie predykcji.

#figure(
  image("../../assets/tiling.png", width: 90%),
  caption: [Wizualizacja strategii kafelkowania. Obraz jest dzielony na nakładające się fragmenty, a wagi (prawy dolny róg) zapewniają płynne przejścia na granicach kafelków.],
) <fig:tiling>

Kluczowym elementem implementacji jest kafelkowanie przestrzenne. Wideo wejściowe jest dzielone na regularną siatkę, nakładających się na siebie, fragmentów o ustalonej rozdzielczości (w eksperymentach przyjęto $192 times 192$ pikseli). Tak zdefiniowane fragmenty są przetwarzane przez model sekwencyjnie, co pozwala na utrzymanie stałego, niskiego zużycia pamięci niezależnie od rozdzielczości materiału wejściowego. Rekonstrukcja pełnej klatki polega na złożeniu przetworzonych fragmentów w jedną całość, przy czym na granicach kafelków ostateczna wartość pikseli jest obliczana poprzez uśrednienie predykcji. Podejście to skutecznie eliminuje widoczność szwów łączenia, zapewniając spójność strukturalną obrazu wynikowego przy minimalnym narzucie obliczeniowym.

== Optymalizacja mechanizmu uwagi

Mimo zastosowania technik kafelkowania, standardowa implementacja mechanizmu uwagi nadal stanowi istotne obciążenie dla przepustowości pamięci i jednostek obliczeniowych konsumenckich kart graficznych. W oryginalnej architekturze FlashVSR wykorzystano mechanizm lokalnie ograniczonej rzadkiej uwagi, który narzuca statyczne okno przetwarzania w celu eliminacji błędów generalizacji pozycyjnej. W niniejszej pracy zmodyfikowano to podejście, zastępując bazowe jądra obliczeniowe rozwiązaniami bardziej efektywnymi pamięciowo i obliczeniowo. Zamiast standardowego algorytmu FlashAttention @dao2022flashattentionfastmemoryefficientexact wdrożono SageAttention @zhang2025sageattentionaccurate8bitattention, natomiast statyczną rzadkość blokową zastąpiono dynamicznym mechanizmem SpargeAttention @zhang2025spargeattentionaccuratetrainingfreesparse.

W celu zminimalizowania kosztownych transferów danych między pamięcią główną HBM a rdzeniami obliczeniowymi, zastosowano metodę SageAttention @zhang2025sageattentionaccurate8bitattention, która umożliwia efektywne wykonywanie operacji w precyzji 8-bitowej. Głównym wyzwaniem w kwantyzacji mechanizmu uwagi jest występowanie wartości odstających (ang. _outliers_) w kanałach macierzy kluczy ($K$), co w naiwnych implementacjach prowadzi do znacznej degradacji jakości generowanego obrazu, objawiającej się rozmyciem tekstur. Zaimplementowane rozwiązanie adresuje ten problem poprzez technikę wygładzania macierzy $K$ (ang. _K-smoothing_), polegającą na odjęciu średniej wartości kanału od macierzy przed kwantyzacją. Operacja ta centruje rozkład wartości, eliminując dominujące odchylenia bez wpływu na wynik końcowy funkcji Softmax, co pozwala na zachowanie wysokiej precyzji operacji mnożenia macierzy $Q$ i $K$ w zredukowanej reprezentacji bitowej.

Uzupełnieniem kwantyzacji jest redukcja liczby operacji realizowana przez mechanizm SpargeAttention @zhang2025spargeattentionaccuratetrainingfreesparse, który wprowadza dynamiczną selekcję bloków w czasie rzeczywistym bez konieczności dodatkowego treningu. Proces ten przebiega dwuetapowo. W pierwszej fazie następuje szybka predykcja istotności: bloki macierzy zapytań ($Q$) i kluczy ($K$) są kompresowane do wektorów reprezentujących ich wartości średnie, co pozwala na efektywne obliczenie estymowanego podobieństwa. Jeżeli wynik tej operacji dla danej pary bloków znajduje się poniżej ustalonego progu, odpowiadający im fragment macierzy uwagi jest klasyfikowany jako nieistotny i nie jest pobierany z pamięci, co eliminuje transfer danych. W drugiej fazie, realizowanej bezpośrednio na poziomie wątków GPU podczas obliczania funkcji Softmax, weryfikowany jest wkład danego bloku w globalną sumę normalizacyjną. W przypadku gdy wkład ten jest znikomy, algorytm dynamicznie rezygnuje z operacji mnożenia przez macierz wartości (V), wykonując obliczenia wyłącznie dla elementów determinujących wynik końcowy.

= Eksperymenty i analiza wyników

W celu zweryfikowania skuteczności proponowanego potoku przetwarzania, przeprowadzono eksperymenty porównawcze, mające na celu zbadanie wpływu technik optymalizacyjnych na jakość generowanego obrazu. Ewaluację oparto na uznanych w środowisku naukowym zbiorach danych oraz zestawie zróżnicowanych metryk jakościowych.

== Zbiory danych

Do weryfikacji wyników wykorzystano dwa standardowe benchmarki o odmiennej charakterystyce: zbiór REDS @reds, zawierający wysokiej jakości sekwencje o dużej dynamice ruchu, wykorzystywany do oceny wierności rekonstrukcji względem idealnego wzorca, oraz zbiór VideoLQ @videolq, składający się z rzeczywistych nagrań o niskiej jakości pobranych z serwisów internetowych, który posłużył do sprawdzenia zdolności generalizacji modelu w obecności złożonych, niesyntetycznych degradacji.

== Metryki oceny

Ocena jakości rekonstrukcji została przeprowadzona uwzględniając zarówno wierność sygnału względem oryginału, jak i subiektywną percepcję wizualną. W grupie metryk referencyjnych zastosowano klasyczny wskaźnik PSNR @psnr (Peak Signal-to-Noise Ratio), który mierzy błąd średniokwadratowy między pikselami obrazu rekonstruowanego a referencyjnego. Mimo powszechności stosowania, PSNR jest krytykowany za słabą korelację z ludzkim postrzeganiem jakości, często faworyzując obrazy gładkie kosztem utraty detali teksturalnych. Dlatego też wyniki uzupełniono o wskaźnik SSIM @ssim (Structural Similarity Index), który lepiej oddaje zmiany w strukturze obrazu, luminancji i kontraście. Najbardziej zaawansowaną miarą w tej grupie jest LPIPS @lpips (Learned Perceptual Image Patch Similarity), obliczający dystans percepcyjny w przestrzeni cech głębokiej sieci neuronowej, co pozwala na znacznie precyzyjniejszą ocenę zgodności tekstur i struktur niż proste operacje na pikselach.

W przypadku braku idealnego wzorca oraz w celu oceny estetyki generowanych obrazów, posłużono się metrykami bezreferencyjnymi. Wykorzystano wskaźnik NIQE @niqe (Naturalness Image Quality Evaluator), badający odchylenia statystyk obrazu od modelu naturalnych scen, co pozwala na wykrycie nienaturalnych artefaktów generacji. Zastosowano również nowoczesne metody oparte na głębokim uczeniu, takie jak MUSIQ @musiq (Multi-scale Image Quality Transformer), który dzięki architekturze Transformer ocenia jakość na wielu skalach jednocześnie, oraz CLIPIQA @clipiqa, wykorzystującą model językowo-wizualny CLIP do oceny semantycznej zgodności obrazu z pozytywnymi wzorcami estetycznymi. Całość uzupełnia specjalistyczna metryka wideo DOVER @dover (Disentangled Objective Video Quality Evaluator), która dekomponuje ocenę na dwa niezależne aspekty: jakość techniczną, wrażliwą na szumy i rozmycia, oraz jakość estetyczną, związaną z kompozycją i stylem, co jest kluczowe dla pełnej oceny modeli generatywnych.

== Środowisko testowe

Eksperymenty przeprowadzono na stacji roboczej wyposażonej w układ graficzny NVIDIA GeForce RTX 3080 z 10 GB pamięci VRAM. Rozmiar pojedynczego kafelka ustalono na $192 times 192$ pikseli, co stanowi wartość pozwalającą na stabilną inferencję. W celu zachowania spójności na granicach fragmentów i eliminacji artefaktów brzegowych, wprowadzono zakładkę o szerokości $24$ pikseli.

== Wyniki eksperymentów

Zestawienie wyników dla modelu referencyjnego, wersji z kafelkowaniem oraz pełnego potoku zoptymalizowanego przedstawiono w #ref(<tab:results>, supplement: "Tabeli"). Analiza danych wskazuje, że dekompozycja obrazu oraz redukcja precyzji atencji wiążą się z marginalnym spadkiem parametrów jakościowych. Zastosowanie kafelkowania skutkuje obniżeniem wskaźnika PSNR na zbiorze REDS o $0.15$ dB, co wynika z ograniczenia globalnego pola recepcyjnego do obszaru kafelka. Integracja zmodyfikowanych mechanizmów SageAttention oraz SpargeAttention wpływa na wynik w stopniu pomijalnym, obniżając PSNR o kolejne $0.03$ dB przy zachowaniu wysokiej wierności strukturalnej (SSIM).

#figure(
  table(
    columns: (auto, auto, 23%, 23%, 23%),
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
    [Zbiór\ danych], [Metryka], [FlashVSR], [FlashVSR +\ kafelkowanie], [FlashVSR +\ kafelkowanie +\ modyfikacja uwagi],

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
  caption: [Porównanie jakości rekonstrukcji dla trzech badanych konfiguracji],
) <tab:results>

= Podsumowanie

Niniejsza praca podjęła problem barier sprzętowych ograniczających powszechne zastosowanie dyfuzyjnych modeli Transformer w zadaniu super-rozdzielczości wideo. Zaproponowane rozwiązanie, integrujące architekturę FlashVSR z mechanizmem kafelkowania przestrzenno-czasowego oraz zoptymalizowanymi algorytmami uwagi (SageAttention, SpargeAttention), pozwoliło na skuteczne przeprowadzenie inferencji na konsumenckiej karcie graficznej z 10 GB pamięci VRAM. Uzyskane wyniki eksperymentalne jednoznacznie wskazują, że redukcja precyzji obliczeń oraz dekompozycja obrazu nie muszą wiązać się z widocznym pogorszeniem jakości generowanych treści. Obserwowany spadek wierności rekonstrukcji stanowi w pełni akceptowalny kompromis inżynierski w zamian za redukcję wymagań pamięciowych. Przedstawione podejście udowadnia, że generowanie wideo o wysokiej wierności jest osiągalne na szeroko dostępnym sprzęcie komputerowym.
