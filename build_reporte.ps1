# Genera "Actividad 05 - Algoritmo genetico.docx" (OpenXML crudo) a partir de los resultados del programa GaJobShop.cs
# Uso: powershell -File build_reporte.ps1 [-CodeUrl <enlace al codigo>]
param([string]$CodeUrl = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem, System.Drawing
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$res  = Join-Path $root 'resultados'
$out  = Join-Path $root 'Actividad 05 - Algoritmo genetico.docx'
if (-not $CodeUrl) { $CodeUrl = 'file:///' + ((Join-Path $root 'GaJobShop.cs') -replace '\\','/' -replace ' ','%20') }
$inv = [Globalization.CultureInfo]::InvariantCulture
function DxNum($s) { [double]::Parse(($s -replace ',', '.'), $inv) }

# ------------------------------------------------------------------ datos
$sum  = Import-Csv (Join-Path $res 'resumen.csv') -Delimiter ';' -Encoding UTF8
$met  = @($sum | Select-Object -First 4)                # 4 metodos
$sumRaw = Get-Content (Join-Path $res 'resumen.csv') -Encoding UTF8
$refv = @{}; foreach ($l in $sumRaw) { $p = $l -split ';'; if ($p[0] -match '^(Cota|Regla|Orden)') { $refv[$p[0]] = [int]$p[1] } }
$LB = $refv['Cota inferior']; $SPT = $refv['Regla SPT']; $MWKR = $refv['Regla MWKR']; $ORD = $refv['Orden de trabajos']
$mw   = Import-Csv (Join-Path $res 'pruebas_mann_whitney.csv') -Delimiter ';' -Encoding UTF8
$conv = Import-Csv (Join-Path $res 'convergencia.csv') -Delimiter ';' -Encoding UTF8
$inst = Import-Csv (Join-Path $res 'instancia.csv') -Delimiter ';' -Encoding UTF8
$MT = @{}; foreach ($m in $met) { $MT[$m.metodo] = $m }
$kB = 'Binaria'; $kP = $met[1].metodo; $kK = $met[2].metodo; $kR = $met[3].metodo
$cols = $conv[0].PSObject.Properties.Name   # generacion + 4 metodos
function DxConv($g, $k) { DxNum ($conv | Where-Object { [int]$_.generacion -eq $g }).$k }
$cnt = @{}; $sumM = @{}
foreach ($r in $inst) { foreach ($t in ($r.PSObject.Properties.Value[1] -split ' > ')) { if ($t -match '^(.+)\((\d+)\)$') { $cnt[$Matches[1]]++; $sumM[$Matches[1]] += [int]$Matches[2] } } }
$nOps = ($cnt.Values | Measure-Object -Sum).Sum

# ------------------------------------------------------------------ utilidades OpenXML
function DxEsc($t) { [System.Security.SecurityElement]::Escape($t) }
function DxRuns($text, $font = $null, $sz = $null, [switch]$italic, $color = $null, [switch]$allBold) {
    $parts = $text -split '\*\*'; $xml = ''; $bold = [bool]$allBold; if ($allBold) { $bold = $true }
    $tog = $false
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($i -gt 0) { $tog = -not $tog }
        $seg = $parts[$i]; if ($seg -eq '') { continue }
        $rpr = ''
        if ($font) { $rpr += "<w:rFonts w:ascii=`"$font`" w:hAnsi=`"$font`" w:cs=`"$font`"/>" }
        if ($tog -or $allBold) { $rpr += '<w:b/>' }
        if ($italic) { $rpr += '<w:i/>' }
        if ($color) { $rpr += "<w:color w:val=`"$color`"/>" }
        if ($sz) { $rpr += "<w:sz w:val=`"$sz`"/><w:szCs w:val=`"$sz`"/>" }
        $lines = $seg -split "`n"
        for ($k = 0; $k -lt $lines.Count; $k++) {
            if ($k -gt 0) { $xml += "<w:r><w:rPr>$rpr</w:rPr><w:br/></w:r>" }
            $xml += "<w:r><w:rPr>$rpr</w:rPr><w:t xml:space=`"preserve`">$(DxEsc $lines[$k])</w:t></w:r>"
        }
    }
    $xml
}
function DxPara($runs, $style = $null, $jc = $null, $keepNext = $false, $after = $null, $before = $null) {
    $ppr = ''
    if ($style) { $ppr += "<w:pStyle w:val=`"$style`"/>" }
    if ($keepNext) { $ppr += '<w:keepNext/>' }
    if ($after -ne $null -or $before -ne $null) { $a = ''; if ($before -ne $null) { $a += " w:before=`"$before`"" }; if ($after -ne $null) { $a += " w:after=`"$after`"" }; $ppr += "<w:spacing$a/>" }
    if ($jc) { $ppr += "<w:jc w:val=`"$jc`"/>" }
    "<w:p><w:pPr>$ppr</w:pPr>$runs</w:p>"
}
function DxText($t, $jc = $null, $keepNext = $false, $after = $null) { DxPara (DxRuns $t) $null $jc $keepNext $after }
function DxHead($t) { DxPara (DxRuns $t) 'Heading1' }
function DxBullet($t) { "<w:p><w:pPr><w:ind w:left=`"425`" w:hanging=`"283`"/></w:pPr>$(DxRuns ([string][char]0x2022 + ' ' + $t))</w:p>" }
function DxCaption($t) { DxPara (DxRuns $t) 'Caption' }
function DxTable($header, $rows, $widths, $center = @(), $fill = $true, $fs = 18, $bold1 = $false, $keep = $true) {
    $w = ($widths | Measure-Object -Sum).Sum
    $x = "<w:tbl><w:tblPr><w:tblW w:w=`"$w`" w:type=`"dxa`"/><w:jc w:val=`"center`"/><w:tblBorders>"
    foreach ($b in 'top', 'left', 'bottom', 'right', 'insideH', 'insideV') { $x += "<w:$b w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"000000`"/>" }
    $x += '</w:tblBorders><w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="40" w:type="dxa"/><w:left w:w="80" w:type="dxa"/><w:bottom w:w="40" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>'
    foreach ($c in $widths) { $x += "<w:gridCol w:w=`"$c`"/>" }
    $x += '</w:tblGrid>'
    $all = @(, $header) + $rows
    for ($r = 0; $r -lt $all.Count; $r++) {
        $isH = ($r -eq 0)
        $x += '<w:tr><w:trPr><w:cantSplit/>' + $(if ($isH) { '<w:tblHeader/>' } else { '' }) + '</w:trPr>'
        for ($c = 0; $c -lt $widths.Count; $c++) {
            $shade = if ($isH) { 'C9DAF8' } elseif ($c -eq 0 -and $fill) { 'FFF2CC' } else { 'FFFFFF' }
            $jc = if ($c -in $center -or $isH) { 'center' } else { 'left' }
            $x += "<w:tc><w:tcPr><w:tcW w:w=`"$($widths[$c])`" w:type=`"dxa`"/><w:shd w:val=`"clear`" w:color=`"auto`" w:fill=`"$shade`"/><w:vAlign w:val=`"center`"/></w:tcPr>"
            foreach ($line in ([string]$all[$r][$c] -split "`n`n")) {
                $kn = if ($keep -and $r -lt $all.Count - 1) { '<w:keepNext/>' } else { '' }
                $x += "<w:p><w:pPr><w:pStyle w:val=`"TableText`"/>$kn<w:jc w:val=`"$jc`"/></w:pPr>$(DxRuns $line 'Arial' $fs -allBold:($isH -or ($c -eq 0 -and $bold1)))</w:p>"
            }
            $x += '</w:tc>'
        }
        $x += '</w:tr>'
    }
    $x + '</w:tbl>' + (DxPara '' 'TableText' $null $false 0)
}
$script:imgId = 0; $script:rels = ''; $script:media = @()
function DxImage($file, $widthCm = 16) {
    $script:imgId++; $id = $script:imgId; $rid = "rIdImg$id"
    $bmp = [System.Drawing.Image]::FromFile($file); $ratio = $bmp.Height / $bmp.Width; $bmp.Dispose()
    $cx = [int64]($widthCm * 360000); $cy = [int64]($cx * $ratio)
    $script:rels += "<Relationship Id=`"$rid`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image`" Target=`"media/img$id.png`"/>"
    $script:media += , @($file, "word/media/img$id.png")
    "<w:p><w:pPr><w:keepNext/><w:jc w:val=`"center`"/><w:spacing w:before=`"120`" w:after=`"40`"/></w:pPr><w:r><w:drawing><wp:inline distT=`"0`" distB=`"0`" distL=`"0`" distR=`"0`"><wp:extent cx=`"$cx`" cy=`"$cy`"/><wp:docPr id=`"$id`" name=`"Figura $id`" descr=`"Figura $id`"/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a=`"http://schemas.openxmlformats.org/drawingml/2006/main`" noChangeAspect=`"1`"/></wp:cNvGraphicFramePr><a:graphic xmlns:a=`"http://schemas.openxmlformats.org/drawingml/2006/main`"><a:graphicData uri=`"http://schemas.openxmlformats.org/drawingml/2006/picture`"><pic:pic xmlns:pic=`"http://schemas.openxmlformats.org/drawingml/2006/picture`"><pic:nvPicPr><pic:cNvPr id=`"$id`" name=`"img$id.png`"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=`"$rid`"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=`"0`" y=`"0`"/><a:ext cx=`"$cx`" cy=`"$cy`"/></a:xfrm><a:prstGeom prst=`"rect`"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
}
function F1($v) { ([double]$v).ToString('0.0', $inv) }
function F2($v) { ([double]$v).ToString('0.00', $inv) }

# ------------------------------------------------------------------ valores derivados para el texto
$mB = $MT[$kB]; $mP = $MT[$kP]; $mK = $MT[$kK]; $mR = $MT[$kR]
$best = ($mB.mejor, $mP.mejor, $mK.mejor | ForEach-Object { [int]$_ } | Measure-Object -Minimum).Minimum
$gapBest = 100 * ($best - $LB) / $LB
$impRand = 100 * ((DxNum $mR.media) - (DxNum $mP.media)) / (DxNum $mR.media)
$impMwkr = 100 * ($MWKR - (DxNum $mP.media)) / $MWKR
$impSpt  = 100 * ($SPT - (DxNum $mP.media)) / $SPT
function DxP($p) { if ([double]$p -lt 0.0001) { '< 0.0001' } else { ([double]$p).ToString('0.0000', $inv) } }
$pv = @{}; foreach ($r in $mw) { $pv["$($r.A)|$($r.B)"] = $r }
$bodyName = @{}

# ------------------------------------------------------------------ contenido
$b = New-Object System.Text.StringBuilder
function Add($x) { [void]$b.Append($x) }

Add (DxPara (DxRuns 'ACTIVIDAD 05' 'Arial' 32 -allBold) 'Title')
Add (DxPara (DxRuns 'Algoritmo genético con tres codificaciones del cromosoma aplicado a la programación de un taller de maquinado (Job-Shop)' 'Arial' 24 -allBold) 'Title' 'center' $false 60)
Add (DxPara (DxRuns 'Alumno: Alonzo Lara Flores     Fecha: 3 de noviembre de 2026' 'Arial' 20) 'Title' 'center' $false 200)

# 1 ----------------------------------------------------------------
Add (DxHead '1. Descripción del problema a ser analizado y tratado con un algoritmo genético')
Add (DxText ('Una planta de manufactura por pedido produce piezas metálicas bajo un esquema de **taller de rutas variables (job-shop)**. En la semana se liberan **15 órdenes de trabajo** (J1 a J15) que deben pasar por **6 centros de trabajo**: Corte, Torno, Fresado, Taladrado, Rectificado e Inspección. Cada orden tiene su propia ruta (todas inician en Corte y terminan en Inspección; las máquinas intermedias y su orden cambian según la pieza), lo que da un total de **' + $nOps + ' operaciones** con tiempos de proceso de 5 a 60 minutos.'))
Add (DxText 'El problema consiste en decidir en qué orden atiende cada máquina las operaciones que le llegan, de modo que todas las órdenes se terminen lo antes posible. Es un problema de programación de la producción (scheduling) clasificado como NP-difícil (Garey, Johnson y Sethi, 1976): el número de secuencias posibles crece de forma factorial, y las reglas de despacho simples (por ejemplo, tiempo de proceso más corto) dejan mucho tiempo ocioso en las máquinas. Por eso es un candidato natural para un algoritmo genético (AG).')
Add (DxText '**Supuestos de la instancia.** Los datos son sintéticos pero realistas; se generaron con una semilla fija (2026) para que el experimento sea reproducible:' $null $true)
Add (DxTable @('Supuesto', 'Descripción') @(
    , @('Tiempos de proceso', 'Enteros en minutos, aleatorios dentro de un rango por máquina: Corte 10–30, Torno 20–60, Fresado 20–60, Taladrado 15–50, Rectificado 15–55 e Inspección 5–20 (incluyen preparación).')
    , @('Rutas', 'Corte primero e Inspección al final; entre ambas, 3 o 4 de las 4 máquinas intermedias en orden aleatorio (cada pieza lleva su propio proceso).')
    , @('Capacidad', 'Una sola máquina por centro de trabajo; procesa una operación a la vez y no se interrumpe una vez iniciada.')
    , @('Precedencia', 'Cada orden sólo puede estar en una máquina a la vez y sus operaciones siguen el orden de su ruta.')
    , @('Disponibilidad', 'Las 15 órdenes y las 6 máquinas están disponibles en el instante 0; sin fallas, mantenimiento ni tiempos de traslado; almacenes intermedios ilimitados.')
) @(2200, 7200))
Add (DxCaption 'Tabla 1. Supuestos del problema.')
$rows = @(); foreach ($r in $inst) { $rows += , @($r.trabajo, ($r.PSObject.Properties.Value[1] -replace ' > ', ' → ')) }
Add (DxText '**Datos de entrada.** La Tabla 2 muestra la ruta de cada orden con su tiempo de proceso entre paréntesis (minutos).' $null $true)
Add (DxTable @('Orden', 'Ruta: máquina (tiempo en min)') $rows @(900, 8500) @() $true 17 $false $false)
Add (DxCaption 'Tabla 2. Instancia sintética: 15 órdenes, 6 máquinas, 86 operaciones.')
$mach = 'Torno', 'Fresado', 'Rectificado', 'Taladrado', 'Corte', 'Inspección'
$rows = @(); foreach ($n in ($cnt.Keys | Sort-Object { -$sumM[$_] })) { $rows += , @($n, [string]$cnt[$n], [string]$sumM[$n]) }
Add (DxTable @('Máquina', 'Operaciones', 'Carga total (min)') $rows @(3000, 2200, 2400) @(1, 2))
Add (DxCaption ('Tabla 3. Carga de trabajo por máquina. La más cargada (' + (($cnt.Keys | Sort-Object { -$sumM[$_] })[0]) + ', ' + (($sumM.Values | Measure-Object -Maximum).Maximum) + ' min) fija una cota inferior para el tiempo total.'))

# 2 ----------------------------------------------------------------
Add (DxHead '2. Objetivo del estudio')
Add (DxText '**Objetivo general.** Minimizar el tiempo total de terminación del taller (**makespan**, C_max) con un algoritmo genético y determinar cuál de tres codificaciones del cromosoma (binaria, permutación con repetición y llaves aleatorias) produce mejores calendarios.')
Add (DxText '**Objetivos específicos.**' $null $true 40)
Add (DxBullet 'Implementar el mismo AG con las tres codificaciones, dejando iguales el decodificador, el tamaño de población, la selección, el elitismo y el presupuesto de evaluaciones.')
Add (DxBullet 'Medir calidad de la solución (mejor, media, peor, desviación), velocidad de convergencia y costo de cómputo en 30 corridas independientes por codificación.')
Add (DxBullet 'Comparar los resultados contra una búsqueda aleatoria con el mismo número de evaluaciones, contra reglas de despacho clásicas y contra la cota inferior.')
Add (DxBullet 'Verificar con la prueba U de Mann–Whitney (α = 0.05) si las diferencias entre codificaciones son estadísticamente significativas.')
Add (DxText ('**Función objetivo.** Minimizar C_max = máx { C_j }, donde C_j es el instante en que termina la última operación de la orden j. La aptitud de un individuo es f = 1 / C_max. La **cota inferior** es LB = máx { carga de la máquina más cargada, longitud de la ruta más larga } = máx { ' + (($sumM.Values | Measure-Object -Maximum).Maximum) + ', 213 } = ' + $LB + ' min; ninguna solución puede ser menor, pero tampoco se sabe si LB es alcanzable.') $null $false 120)

# 3 ----------------------------------------------------------------
Add (DxHead '3. Las tres formas de codificar el cromosoma')
Add (DxTable @('Codificación', 'Cómo se representa una solución', 'Longitud y espacio de búsqueda') @(
    , @('A. Binaria', 'Cadena de bits. Cada operación tiene un bloque de 8 bits; su valor entero (0 a 255) es la prioridad de la operación (menor valor = se atiende antes).', ('86 × 8 = 688 bits.' + "`n" + 'Espacio de 2^688 cadenas.'))
    , @('B. Permutación con repetición (entera)', 'Vector de enteros donde cada número es una orden y aparece tantas veces como operaciones tiene (J1 aparece 6 veces, J6 aparece 5, etc.). La k-ésima aparición de la orden j representa su k-ésima operación; su prioridad es la posición en el vector.', ('86 genes enteros.' + "`n" + 'Permutaciones de un multiconjunto; todas son válidas.'))
    , @('C. Llaves aleatorias (real)', 'Vector de números reales en [0, 1), uno por operación. La llave es la prioridad de la operación (Bean, 1994).', ('86 genes reales.' + "`n" + 'Espacio continuo de 86 dimensiones.'))
) @(2000, 4900, 2500))
Add (DxCaption 'Tabla 4. Codificaciones comparadas.')
Add (DxText 'Se eligieron porque son las tres familias clásicas de representación (binaria, entera/permutación y real) y porque cada una exige operadores genéticos distintos. Las tres terminan produciendo siempre un calendario factible, porque la factibilidad la garantiza el decodificador y no el cromosoma.')

# 4 ----------------------------------------------------------------
Add (DxHead '4. Genotipos y fenotipos')
Add (DxText 'El **genotipo** es el cromosoma tal como lo manipula el AG; el **fenotipo** es el calendario de producción que resulta de decodificarlo: instante de inicio y de fin de cada operación en su máquina (el diagrama de Gantt) y el makespan.')
Add (DxTable @('Codificación', 'Genotipo', 'Ejemplo (primeros genes)', 'Fenotipo') @(
    , @('A. Binaria', 'Cadena de 688 bits (86 bloques de 8 bits).', ('01101001 11100010 00010111 …' + "`n`n" + 'Prioridades de las operaciones 1, 2 y 3: 105, 226 y 23.'), 'Calendario de 86 operaciones con inicio, fin y makespan.')
    , @('B. Permutación con repetición', 'Vector de 86 números de orden (multiconjunto con n_j copias de j).', ('[3, 1, 3, 2, 1, 2, …]' + "`n`n" + 'Primero la operación 1 de J3 (prioridad 1), luego la 1 de J1 (2), la 2 de J3 (3), …'), 'Mismo tipo de calendario (diagrama de Gantt).')
    , @('C. Llaves aleatorias', 'Vector de 86 reales en [0, 1).', ('[0.71, 0.08, 0.45, …]' + "`n`n" + 'La operación con la llave más baja tiene mayor prioridad.'), 'Mismo tipo de calendario (diagrama de Gantt).')
) @(1700, 2300, 3400, 2000) @() $true 17)
Add (DxCaption 'Tabla 5. Genotipos, ejemplos y fenotipo.')
Add (DxText '**Decodificación (genotipo → fenotipo).** Las tres codificaciones se convierten primero en un vector de prioridades, una por operación (binaria: el entero del bloque; permutación: la posición; llaves: el valor de la llave). Después se aplica el mismo algoritmo de Giffler y Thompson (1960), que construye un calendario activo:' $null $true 40)
Add (DxBullet 'Cada orden tiene una operación pendiente (la siguiente de su ruta). Para cada una se calcula el instante más temprano en que podría terminar: inicio = máx { fin de la orden, máquina libre } más su tiempo de proceso.')
Add (DxBullet 'Se toma la máquina m* de la operación que terminaría primero y se arma el conjunto de conflicto: operaciones pendientes en m* que podrían empezar antes de ese instante.')
Add (DxBullet 'De ese conjunto se programa la de mayor prioridad (menor valor en el genotipo) y se actualizan los tiempos de la orden y de la máquina. Se repite 86 veces.')
Add (DxText 'Como el decodificador es el mismo, las diferencias de resultados provienen de la codificación y de sus operadores genéticos asociados, no de la forma de construir el calendario.' $null $false 120)

# 5 ----------------------------------------------------------------
Add (DxHead '5. Métodos usados en cada una de las 7 etapas del algoritmo genético')
Add (DxText 'Se consideraron las siguientes siete etapas del ciclo del AG: (1) codificación, (2) población inicial, (3) evaluación, (4) selección, (5) cruza, (6) mutación y (7) reemplazo y criterio de paro.' $null $true)
Add (DxTable @('Etapa', 'A. Binaria', 'B. Permutación con repetición', 'C. Llaves aleatorias') @(
    , @('1. Codificación', 'Cadena de 688 bits (8 bits por operación).', 'Vector de 86 enteros (número de orden repetido n_j veces).', 'Vector de 86 reales en [0, 1).')
    , @('2. Población inicial', '100 individuos con bits equiprobables.', '100 permutaciones aleatorias del multiconjunto (Fisher–Yates).', '100 vectores con U(0, 1).')
    , @('3. Evaluación', 'Decodificar (Giffler–Thompson) y calcular C_max; aptitud 1 / C_max.', 'Igual que A.', 'Igual que A.')
    , @('4. Selección', 'Torneo de tamaño 3 (con reemplazo).', 'Igual que A.', 'Igual que A.')
    , @('5. Cruza', 'Dos puntos, pc = 0.9.', 'POX (Precedence Operation Crossover): un subconjunto aleatorio de órdenes conserva sus posiciones del padre 1 y el resto se rellena en el orden del padre 2; pc = 0.9.', 'Uniforme (cada gen viene de un padre al azar con p = 0.5); pc = 0.9.')
    , @('6. Mutación', 'Inversión de bit con p = 2/688 ≈ 0.0029 por bit (unos 2 bits por individuo).', 'Intercambio de dos posiciones al azar con probabilidad 0.30 por individuo.', 'Perturbación gaussiana N(0, 0.15²) con p = 2/86 por gen, recortada a [0, 1).')
    , @('7. Reemplazo y paro', 'Generacional con elitismo (los 2 mejores pasan intactos). Paro a las 300 generaciones (≈ 29,500 evaluaciones por corrida).', 'Igual que A.', 'Igual que A.')
) @(1500, 2300, 3300, 2300) @() $true 17)
Add (DxCaption 'Tabla 6. Métodos de cada etapa por codificación. Parámetros comunes: población 100, 300 generaciones, 30 corridas independientes (semillas 1000 a 1029).')
Add (DxText 'Para que la comparación sea justa, todas las codificaciones usan la misma población, selección, elitismo y número de evaluaciones. Los parámetros de mutación y cruza se fijaron con valores usuales antes de correr los experimentos y no se afinaron por separado para cada codificación.')

# 6 ----------------------------------------------------------------
Add (DxHead '6. Código que apoya el cumplimiento del objetivo')
Add (DxText 'El programa está escrito en C# (compilado con el compilador incluido en .NET Framework 4, sin dependencias externas). Lee la instancia sintética, ejecuta el AG con las tres codificaciones y la búsqueda aleatoria, calcula las estadísticas y genera los archivos CSV y las gráficas que aparecen en este informe.' $null $true 60)
Add ("<w:p><w:pPr><w:jc w:val=`"left`"/></w:pPr>$(DxRuns '**Enlace al código:** ')<w:hyperlink r:id=`"rIdCode`"><w:r><w:rPr><w:rStyle w:val=`"Hyperlink`"/></w:rPr><w:t>$(DxEsc $CodeUrl)</w:t></w:r></w:hyperlink></w:p>")
Add (DxTable @('Componente (clase)', 'Función') @(
    , @('Instance', 'Genera la instancia sintética (rutas y tiempos) con semilla fija y calcula la cota inferior.')
    , @('Decoder', 'Convierte un vector de prioridades en un calendario (Giffler–Thompson) y devuelve el makespan.')
    , @('BinaryCodec, PermCodec, KeysCodec', 'Una clase por codificación: individuo aleatorio, decodificación a prioridades, cruza y mutación.')
    , @('Ga', 'Ciclo del AG (selección por torneo, elitismo, reemplazo) y la búsqueda aleatoria de referencia.')
    , @('Stats y Charts', 'Estadísticos, prueba de Mann–Whitney y gráficas (convergencia, cajas y diagrama de Gantt).')
    , @('Program', 'Ejecuta 30 corridas por método, las reglas de despacho y escribe los resultados en la carpeta resultados.')
) @(3000, 6400))
Add (DxCaption 'Tabla 7. Estructura del código (GaJobShop.cs).')
Add (DxText 'Los resultados completos (CSV, gráficas y el calendario de la mejor solución) están en la carpeta resultados junto al código. Las semillas son fijas, de modo que al volver a ejecutar el programa se obtienen los mismos valores de makespan.')

# 7 ----------------------------------------------------------------
Add (DxHead '7. Resultados')
$rows = @()
foreach ($m in $met) { $rows += , @($m.metodo, $m.mejor, (F1 $m.media), $m.peor, (F2 $m.desv_est), ((F1 $m.'brecha_media_%') + ' %'), (F1 $m.gen_media_mejor), ([string][int](DxNum $m.tiempo_medio_ms))) }
Add (DxText ('**Calidad de las soluciones.** La Tabla 8 resume el makespan final de 30 corridas independientes por método (menor es mejor). La brecha se mide contra la cota inferior de ' + $LB + ' min.') $null $true)
Add (DxTable @('Método', 'Mejor', 'Media', 'Peor', 'Desv. est.', 'Brecha media', 'Gen. del mejor', 'Tiempo (ms)') $rows @(2300, 800, 900, 800, 1000, 1100, 1300, 1200) @(1, 2, 3, 4, 5, 6, 7) $true 17)
Add (DxCaption ('Tabla 8. Makespan (min) en 30 corridas. "Gen. del mejor" es la generación promedio en que se halló la mejor solución de cada corrida (para la búsqueda aleatoria se agrupan las evaluaciones en 300 bloques). Tiempo medio por corrida de ≈ 29,500 evaluaciones.'))
Add (DxTable @('Referencia', 'Makespan (min)') @(
    , @('Cota inferior (LB)', [string]$LB)
    , @('Regla SPT (tiempo de proceso más corto)', [string]$SPT)
    , @('Regla MWKR (más trabajo restante)', [string]$MWKR)
    , @('Despacho por orden de trabajos (J1, J2, …)', [string]$ORD)
    , @(('Mejor solución del AG (' + $kP + ')'), [string]$best)
) @(5800, 2200) @(1))
Add (DxCaption 'Tabla 9. Valores de referencia deterministas, calculados con el mismo decodificador.')
Add (DxImage (Join-Path $res 'convergencia.png') 15)
Add (DxCaption 'Figura 1. Convergencia: makespan promedio del mejor individuo por generación (30 corridas).')
Add (DxImage (Join-Path $res 'cajas.png') 15)
Add (DxCaption 'Figura 2. Distribución del makespan final por método (caja: cuartiles y mediana; puntos: cada corrida).')
Add (DxImage (Join-Path $res 'gantt_mejor.png') 16)
Add (DxCaption ('Figura 3. Diagrama de Gantt (fenotipo) de la mejor solución global: ' + $best + ' min. Cada color es una orden de trabajo.'))
$g50 = 50
$rows = @(); foreach ($k in $kB, $kP, $kK, $kR) { $rows += , @($k, (F1 (DxConv 0 $k)), (F1 (DxConv 50 $k)), (F1 (DxConv 300 $k))) }
Add (DxText '**Evolución del mejor makespan promedio.**' $null $true 40)
Add (DxTable @('Método', 'Generación 0', 'Generación 50', 'Generación 300') $rows @(3400, 1900, 2000, 2100) @(1, 2, 3))
Add (DxCaption 'Tabla 10. Makespan promedio del mejor individuo en tres momentos de la evolución.')
$rows = @()
$pairs = @(@($kB, $kP), @($kB, $kK), @($kP, $kK), @($kB, $kR), @($kP, $kR), @($kK, $kR))
foreach ($pr in $pairs) { $r = $pv["$($pr[0])|$($pr[1])"]; $rows += , @($pr[0], $pr[1], (F2 $r.z), (DxP $r.p_bilateral), $(if ([double]$r.p_bilateral -lt 0.05) { 'Sí' } else { 'No' })) }
Add (DxText '**Significancia estadística.** Prueba U de Mann–Whitney bilateral (aproximación normal con corrección por empates), α = 0.05, 30 corridas contra 30:' $null $true 40)
Add (DxTable @('Método A', 'Método B', 'z', 'Valor p', '¿Diferencia significativa?') $rows @(2300, 2300, 900, 1400, 2500) @(2, 3, 4) $true 17)
Add (DxCaption 'Tabla 11. Comparaciones por pares del makespan final.')

# 8 ----------------------------------------------------------------
Add (DxHead '8. Interpretación y análisis de los resultados')
Add (DxText ('**El AG sí aporta valor.** Con cualquier codificación supera por mucho a la búsqueda aleatoria con el mismo número de evaluaciones (p < 0.0001) y a las reglas de despacho: la media de la permutación con repetición (' + (F1 $mP.media) + ' min) es ' + (F1 $impRand) + ' % menor que la de la búsqueda aleatoria, ' + (F1 $impMwkr) + ' % menor que MWKR (' + $MWKR + ' min) y ' + (F1 $impSpt) + ' % menor que SPT (' + $SPT + ' min). La mejor solución global (' + $best + ' min) queda a ' + (F1 $gapBest) + ' % de la cota inferior.'))
Add (DxText ('**Ranking de codificaciones.** Quedó así: permutación con repetición (media ' + (F1 $mP.media) + ', desv. ' + (F2 $mP.desv_est) + '), llaves aleatorias (' + (F1 $mK.media) + ', desv. ' + (F2 $mK.desv_est) + ') y binaria (' + (F1 $mB.media) + ', desv. ' + (F2 $mB.desv_est) + '). Las tres diferencias son estadísticamente significativas (Tabla 11); la menor es binaria contra llaves (p = ' + (DxP $pv["$kB|$kK"].p_bilateral) + '). La permutación además es la más estable: su peor corrida (' + $mP.peor + ' min) es mejor que la media de las otras dos codificaciones.'))
Add (DxText '**Por qué ganó la permutación (explicaciones probables, no probadas con experimentos adicionales).**' $null $true 40)
Add (DxBullet 'Su genotipo ya es un orden de procesamiento: los cambios que hacen la cruza POX y el intercambio se traducen en cambios de secuencia pequeños y con sentido, y POX conserva el orden relativo de las órdenes que hereda de cada padre (bloques constructivos).')
Add (DxBullet 'En la binaria, un solo bit de alto peso cambia drásticamente la prioridad de una operación, y la cruza de dos puntos corta bloques sin relación con la estructura de las órdenes. Además, 688 bits son una representación muy redundante: sólo importa el orden relativo de las prioridades, no su valor exacto.')
Add (DxText ('En las llaves aleatorias la mutación gaussiana permite ajustes finos y la cruza uniforme no rompe bloques, por eso queda a medio camino; sin embargo también es redundante (muchos vectores distintos producen la misma secuencia) y su espacio continuo es más lento de explorar. La población inicial de la permutación ya parte de un mejor makespan (' + (F1 (DxConv 0 $kP)) + ' contra ≈ ' + (F1 (DxConv 0 $kB)) + ' de las otras): al ordenar por posición, las operaciones de una misma orden reciben prioridades crecientes, lo que favorece que cada orden avance de forma continua por su ruta (hipótesis).'))
Add (DxText ('**Convergencia y costo.** La permutación converge más rápido (generación media del mejor: ' + (F1 $mP.gen_media_mejor) + ' contra ' + (F1 $mK.gen_media_mejor) + ' de las llaves y ' + (F1 $mB.gen_media_mejor) + ' de la binaria) y casi se estabiliza antes de la generación 60 (Figura 1), lo que sugiere riesgo de convergencia prematura; la binaria seguía mejorando lentamente al terminar. El costo de cómputo es similar (' + ([string][int](DxNum $mK.tiempo_medio_ms)) + ' a ' + ([string][int](DxNum $mB.tiempo_medio_ms)) + ' ms por corrida) porque casi todo el tiempo lo consume el decodificador, que es común; la binaria cuesta un poco más por el paso de bits a enteros.'))
Add (DxText ('**Limitaciones.** (1) Se usó una sola instancia sintética; el ranking podría cambiar con otros tamaños o cargas. (2) No se afinaron los parámetros para cada codificación (la binaria y las llaves podrían mejorar con otras tasas de mutación). (3) La comparación mide codificación y operadores juntos, tal como se usan en la práctica, no la codificación aislada. (4) Ninguna corrida alcanzó la cota inferior; no se sabe si el óptimo está por debajo de ' + $best + ' min. (5) Los tiempos dependen del equipo.'))
Add (DxText '**Recomendaciones.** Para programar un taller real conviene usar permutación con repetición y POX; como mejoras se sugieren aumentar la diversidad (mayor mutación o reinicios), hibridar con búsqueda local y probar con más instancias y con tiempos de preparación o fechas de entrega.')

# 9 ----------------------------------------------------------------
Add (DxHead 'Conclusión')
Add (DxPara (DxRuns ('Se aplicó un algoritmo genético a un taller de maquinado de 15 órdenes, 6 máquinas y 86 operaciones, comparando las codificaciones binaria, de permutación con repetición y de llaves aleatorias bajo las mismas condiciones. Las tres mejoran claramente a la búsqueda aleatoria y a las reglas de despacho, pero la permutación con repetición obtuvo el mejor y más estable resultado (media ' + (F1 $mP.media) + ' min, mejor ' + $best + ' min, ' + (F1 $gapBest) + ' % sobre la cota inferior), seguida de las llaves aleatorias y de la binaria; las diferencias son significativas. La forma de codificar el cromosoma, por tanto, influye tanto como el resto de los operadores: conviene que el genotipo exprese directamente la estructura del problema (aquí, un orden de procesamiento).') 'Calibri' 22) $null 'both')

# 10 ---------------------------------------------------------------
Add (DxHead 'Referencias bibliográficas')
$refs = @(
    'Bean, J. C. (1994). Genetic algorithms and random keys for sequencing and optimization. ORSA Journal on Computing, 6(2), 154–160.',
    'Bierwirth, C. (1995). A generalized permutation approach to job shop scheduling with genetic algorithms. OR Spektrum, 17(2–3), 87–92.',
    'Cheng, R., Gen, M., y Tsujimura, Y. (1996). A tutorial survey of job-shop scheduling problems using genetic algorithms—I. Representation. Computers & Industrial Engineering, 30(4), 983–997.',
    'Davis, L. (1985). Job shop scheduling with genetic algorithms. En Proceedings of the First International Conference on Genetic Algorithms and their Applications (pp. 136–140). Lawrence Erlbaum.',
    'Eiben, A. E., y Smith, J. E. (2015). Introduction to Evolutionary Computing (2.ª ed.). Springer.',
    'Garey, M. R., Johnson, D. S., y Sethi, R. (1976). The complexity of flowshop and jobshop scheduling. Mathematics of Operations Research, 1(2), 117–129.',
    'Giffler, B., y Thompson, G. L. (1960). Algorithms for solving production-scheduling problems. Operations Research, 8(4), 487–503.',
    'Goldberg, D. E. (1989). Genetic Algorithms in Search, Optimization, and Machine Learning. Addison-Wesley.',
    'Gonçalves, J. F., y Resende, M. G. C. (2011). Biased random-key genetic algorithms for combinatorial optimization. Journal of Heuristics, 17(5), 487–525.',
    'Holland, J. H. (1975). Adaptation in Natural and Artificial Systems. University of Michigan Press.',
    'Mann, H. B., y Whitney, D. R. (1947). On a test of whether one of two random variables is stochastically larger than the other. The Annals of Mathematical Statistics, 18(1), 50–60.',
    'Nakano, R., y Yamada, T. (1991). Conventional genetic algorithm for job shop problems. En Proceedings of the Fourth International Conference on Genetic Algorithms (pp. 474–479). Morgan Kaufmann.',
    'Pinedo, M. L. (2016). Scheduling: Theory, Algorithms, and Systems (5.ª ed.). Springer.'
)
foreach ($r in $refs) { Add ("<w:p><w:pPr><w:ind w:left=`"567`" w:hanging=`"567`"/><w:jc w:val=`"left`"/><w:spacing w:after=`"80`"/></w:pPr>$(DxRuns $r 'Calibri' 21)</w:p>") }

# ------------------------------------------------------------------ partes del paquete
$ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"'
$sect = '<w:sectPr><w:footerReference w:type="default" r:id="rIdFooter"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1304" w:right="1418" w:bottom="1304" w:left="1418" w:header="709" w:footer="567" w:gutter="0"/></w:sectPr>'
$docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "<w:document $ns><w:body>" + $b.ToString() + $sect + '</w:body></w:document>'
$styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
  '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="es-MX"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>' +
  '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:pPr><w:jc w:val="both"/></w:pPr></w:style>' +
  '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="0" w:after="80"/><w:jc w:val="center"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/></w:rPr></w:style>' +
  '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="280" w:after="120"/><w:jc w:val="left"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:b/><w:color w:val="000000"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>' +
  '<w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="40" w:after="160"/><w:jc w:val="center"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:i/><w:sz w:val="17"/><w:szCs w:val="17"/></w:rPr></w:style>' +
  '<w:style w:type="paragraph" w:styleId="TableText"><w:name w:val="Table Text"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="left"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>' +
  '<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>' +
  '</w:styles>'
$footer = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">Actividad 05 – Algoritmo genético   |   Página </w:t></w:r><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="16"/></w:rPr><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r></w:p></w:ftr>'
$docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
  '<Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>' +
  "<Relationship Id=`"rIdCode`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink`" Target=`"$(DxEsc $CodeUrl)`" TargetMode=`"External`"/>" + $script:rels + '</Relationships>'
$ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>' +
  '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>'
$rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'

if (Test-Path $out) { Remove-Item $out -Force }
$zip = [System.IO.Compression.ZipFile]::Open($out, 'Create')
$enc = New-Object System.Text.UTF8Encoding $false
function DxAdd($name, $text) { $e = $zip.CreateEntry($name); $s = $e.Open(); $by = $enc.GetBytes($text); $s.Write($by, 0, $by.Length); $s.Close() }
DxAdd '[Content_Types].xml' $ct; DxAdd '_rels/.rels' $rootRels; DxAdd 'word/document.xml' $docXml; DxAdd 'word/styles.xml' $styles; DxAdd 'word/footer1.xml' $footer; DxAdd 'word/_rels/document.xml.rels' $docRels
foreach ($m in $script:media) { [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $m[0], $m[1]) }
$zip.Dispose()
"Generado: $out"
