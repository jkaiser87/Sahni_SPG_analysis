#@ File(label = "Choose main folder", style="directory") dir
@Grab('com.jmatio:jmatio:1.0')  

import ij.*
import ij.gui.*
import ij.plugin.*
import ij.process.*
import ij.measure.ResultsTable
import javax.swing.*
import java.awt.*
import java.awt.event.*
import groovy.transform.Field
import java.util.Timer
import java.util.TimerTask
import java.io.*
import com.jmatio.io.MatFileReader
import com.jmatio.types.*
import ij.IJ
import java.awt.Window
import ij.gui.Overlay
import ij.gui.Roi
import java.awt.Color
import ij.plugin.Duplicator
import ij.plugin.HyperStackConverter
import ij.WindowManager
import ij.process.ImageConverter
import ij.io.FileSaver
import ij.ImagePlus

// --- Globals ---
@Field def impFront
@Field def impSide
@Field def frontFiles
@Field def fileIndex = -1        // which animal
@Field def reachIndex = 0        // which reach within animal
@Field def reaches = []          // reach structs loaded from MAT (placeholder list of maps)
@Field def currentFrontFile
@Field def currentSideFile
@Field Timer playTimer = null
@Field def playing = false
@Field def buffer = 100          // buffer frames around each reach
@Field def labelsCSV              // results table to accumulate labels
@Field def coreID = ""
@Field def animals = []
@Field def videoLengths = [:]  
@Field int playStartSide = 1, playEndSide = 1
@Field int playStartFront = 1, playEndFront = 1
@Field int playLen = 0
@Field def excluded = [] as Set
@Field int currentOffset = 0             // front - side at the moment we lock it in
@Field int baseWindowLen = 0             // length of the side window for this reach
@Field JLabel lblOffset = new JLabel("Offset: 0")
@Field def alignmentMap = [:]
@Field boolean useManualAlignment = false
@Field int alignedSideStart = 0
@Field int alignedSideEnd   = 0
@Field int alignedFrontStart = 0
@Field int alignedFrontEnd   = 0
@Field boolean lastReachFlag = false
@Field def loopCount = [0]
@Field boolean autoPlayFlag = false
@Field int tickK = 0
@Field int tickLoop = 0



// --- Helpers needed on load ---
def buildAnimals(File dir) {
    def mats = listMatReaches(dir)
    def frontDir = new File(dir, "Front")
    def sideDir  = new File(dir, "Side")

    animals.clear()
    mats.each { f ->
        def name = f.name
        def cid = name.substring(0, name.toLowerCase().lastIndexOf("_reaches.mat"))

        def front = findVideoByCoreAndTag(frontDir, cid, "Front")
        def side  = findVideoByCoreAndTag(sideDir,  cid, "Side")

        // read total reaches from MAT
        def (nReaches, _) = countReachesAndLabeled(f)

        // read labeled count from CSV (if exists)
        def labelsMap = loadLabelsFromCSV(cid)
        def nLabeled = labelsMap.size()

        animals << [
            coreID   : cid,
            matFile  : f,
            frontFile: front,
            sideFile : side,
            nReaches : nReaches,
            nLabeled : nLabeled
        ]
    }
    return animals
}


def loadReachesMat(coreID) {
    def outDir = new File(dir, "OUT")
    def matFile = new File(outDir, "${coreID}_reaches.mat")
    if (!matFile.exists()) {
        IJ.error("Missing reaches.mat for ${coreID}")
        return []
    }

    def reader = new MatFileReader(matFile)
    def content = reader.getContent()
    def reachesVar = content.get("reaches")

    if (!(reachesVar instanceof MLStructure)) {
        IJ.error("No struct array 'reaches' in ${matFile.name}")
        return []
    }

    def reachesStruct = reachesVar as MLStructure
    def nReaches = reachesStruct.getM() * reachesStruct.getN()
    def reaches = []

    (0..<nReaches).each { idx ->
        def reach = [:]

        // numeric fields
        reach.startFrame = (reachesStruct.getField("startFrame", idx) instanceof MLDouble) ?
            (int) reachesStruct.getField("startFrame", idx).get(0,0) : 0
        reach.endFrame = (reachesStruct.getField("endFrame", idx) instanceof MLDouble) ?
            (int) reachesStruct.getField("endFrame", idx).get(0,0) : 0

        // sideFrames array
        def sideArr = []
        def side = reachesStruct.getField("sideFrames", idx)
        if (side instanceof MLDouble) {
            for (i in 0..<side.getSize()) sideArr << (int) side.get(i)
        }
        reach.sideFrames = sideArr

        // frontFrames array
        def frontArr = []
        def front = reachesStruct.getField("frontFrames", idx)
        if (front instanceof MLDouble) {
            for (i in 0..<front.getSize()) frontArr << (int) front.get(i)
        }
        reach.frontFrames = frontArr

        // label (optional)
        def labelField = reachesStruct.getField("label", idx)
        reach.label = (labelField instanceof MLChar) ? labelField.content : ""

        reaches << reach
    }

    return reaches
}

def listMatReaches(File baseDir) {
    def outDir = new File(baseDir, "OUT")
    if (!outDir.exists()) outDir.mkdirs()
    return outDir.listFiles()?.findAll { it.name.toLowerCase().endsWith("_reaches.mat") }?.sort { it.name } ?: []
}

def findVideoByCoreAndTag(File folder, String coreID, String tag) {
    if (!folder.exists()) return null

    // Example:
    // coreID = "ANIMAL123_baseline"
    // tag = "Front" → ANIMAL123_Front_baseline.mp4
    // tag = "Side"  → ANIMAL123_Side_baseline.mp4
    def expectedName = coreID.replaceFirst("_", "_${tag}_") + ".mp4"

    def f = new File(folder, expectedName)
    if (f.exists()) {
        return f
    } else {
        IJ.log("❌ Expected video not found: ${f.absolutePath}")
        return null
    }
}

def countReachesAndLabeled(File matFile) {
    try {
        def reader = new MatFileReader(matFile)
        def content = reader.getContent()
        def var = content.get("reaches")
        if (!(var instanceof MLStructure)) return [0, 0]
        def s = (MLStructure) var
        def n = s.getM() * s.getN()
        int labeled = 0
        for (int i=0; i<n; i++) {
            def lab = s.getField("label", i)
            if (lab instanceof MLChar) {
                def txt = ((MLChar)lab).getString()
                if (txt != null && txt.trim().length() > 0) labeled++
            }
        }
        return [n, labeled]
    } catch (Throwable t) {
        IJ.log("Warning: failed to read ${matFile.name}: ${t.getMessage()}")
        return [0, 0]
    }
}

def loadExcluded() {
    def exFile = new File(new File(dir, "OUT"), "exclude_table.csv")
    excluded.clear()
    if (exFile.exists()) {
        exFile.eachLine { line, i ->
            if (i == 0 || !line) return // skip header
            def parts = line.split(",")
            if (parts.size() >= 2 && parts[1].trim() == "1") {
                excluded.add(parts[0].trim())
            }
        }
    }
}

def loadAlignmentTable() {
    def map = [:]
    def f = new File(new File(dir, "OUT"), "alignment_table.csv")
    if (!f.exists()) {
        IJ.log("⚠️ No alignment_table.csv found in ${f.parent}")
        return map
    }

    f.eachLine { line, idx ->
         // skip header line(s)
        if (idx == 0 || line.toLowerCase().contains("coreid")) return 
        def parts = line.split(",")
        if (parts.size() >= 7) {
            def cid    = parts[0].trim()
            def side1  = parts[1].isInteger() ? parts[1].toInteger() : null
            def front1 = parts[2].isInteger() ? parts[2].toInteger() : null
            def off1   = parts[3].isInteger() ? parts[3].toInteger() : null
            def side2  = parts[4].isInteger() ? parts[4].toInteger() : null
            def front2 = parts[5].isInteger() ? parts[5].toInteger() : null
            def off2   = parts[6].isInteger() ? parts[6].toInteger() : null

            map[cid] = [
                sideFrame1: side1, frontFrame1: front1, offStart: off1,
                sideFrame2: side2, frontFrame2: front2, offEnd: off2
            ]
        } else {
            IJ.log("⚠️ Skipping line ${idx+1} in alignment_table.csv (not enough columns)")
        }
    }
    return map
}

String.metaClass.isInteger = { ->
    delegate ==~ /^-?\d+$/
}

// fill previous reachLabelcsv files with offset (only needed temporarily)
def backfillOffsets(coreID) {
    def outDir = new File(dir, "OUT")
    def csvFile = new File(outDir, "${coreID}_reachLabels.csv")
    if (!csvFile.exists()) {
        IJ.log("⏭ No CSV yet for ${coreID}, skipping backfill")
        return
    }

    def reaches = loadReachesMat(coreID)
    if (!reaches || reaches.isEmpty()) return

    def labelsMap = loadLabelsFromCSV(coreID)

    def header = "CoreID,ReachIndex,SideStart,SideEnd,FrontStart,FrontEnd,Offset,Label"
    def updatedRows = []
    int added = 0

    reaches.eachWithIndex { r, idx ->
        def sideStart  = r.sideFrames ? r.sideFrames.min() : 0
        def sideEnd    = r.sideFrames ? r.sideFrames.max() : 0
        def frontStart = r.frontFrames ? r.frontFrames.min() : 0
        def frontEnd   = r.frontFrames ? r.frontFrames.max() : 0

        def entry = labelsMap[idx+1]
        def lbl   = entry?.label ?: ""   // keep unlabeled blank
        def off   = entry?.offset

        if (off == null) {
            off = frontStart - sideStart
            added++
        }

        updatedRows << "${coreID},${idx+1},${sideStart},${sideEnd},${frontStart},${frontEnd},${off},${lbl}"
    }

    csvFile.text = ([header] + updatedRows).join("\n") + "\n"
    IJ.log("✔ ${coreID}: added ${added} offsets, kept ${updatedRows.size() - added}")
}

animals = buildAnimals(dir)
// animals.each { a ->
//     backfillOffsets(a.coreID)
// }
loadExcluded()

// === GUI ===
def frame = new JFrame("Reach Classification Tool")
frame.setLayout(new BoxLayout(frame.getContentPane(), BoxLayout.Y_AXIS))

// --- Animal table ---
@Field def colNames = ["#", "CoreID", "Reaches", "Labeled", "Excluded", "OffsetStart", "OffsetEnd", "ReachMAT"]

def rowList = []
alignmentMap = loadAlignmentTable()

animals.eachWithIndex { a, idx ->
    def al = alignmentMap[a.coreID] ?: [offStart: "", offEnd: ""]
    rowList << [
    idx + 1,
    a.coreID,
    a.nReaches,
    a.nLabeled,
    excluded.contains(a.coreID),   // true/false for Excluded column
    al.offStart,
    al.offEnd,
    a.matFile.name
    ] as Object[]

}

// Build model with column names only
@Field model = new javax.swing.table.DefaultTableModel(colNames as Object[], 0) {
    @Override
    boolean isCellEditable(int r, int c) { false }

    @Override
    Class<?> getColumnClass(int columnIndex) {
        if (columnIndex == 4) return Boolean.class
        return Object.class
    }

}

// Fill rows
rowList.each { row -> model.addRow(row as Object[]) }

// Build table
@Field def tblAnimals = new JTable(model)
tblAnimals.setSelectionMode(ListSelectionModel.SINGLE_SELECTION)
tblAnimals.setFillsViewportHeight(true)
tblAnimals.setPreferredScrollableViewportSize(new Dimension(800, 300)) // taller table

// Put table in scroll pane
def scrollAnimals = new JScrollPane(tblAnimals)
frame.add(scrollAnimals)

// Hide the last column (ReachMAT)
tblAnimals.getColumnModel().removeColumn(tblAnimals.getColumnModel().getColumn(7))

// After you create tblAnimals
tblAnimals.setAutoResizeMode(JTable.AUTO_RESIZE_SUBSEQUENT_COLUMNS) // prevent Swing from overriding your widths

def colModel = tblAnimals.getColumnModel()

// Example widths (pixels):
colModel.getColumn(0).setPreferredWidth(30)   // "#"
colModel.getColumn(1).setPreferredWidth(250)  // "CoreID"
colModel.getColumn(2).setPreferredWidth(100)   // "Reaches"
colModel.getColumn(3).setPreferredWidth(300)
colModel.getColumn(3).setMinWidth(100)
colModel.getColumn(4).setPreferredWidth(50)   // "Excluded" (checkbox)
colModel.getColumn(5).setPreferredWidth(90)   // "OffsetStart"
colModel.getColumn(6).setPreferredWidth(90)   // "OffsetEnd"


// Label to show current selection
@Field def lblAnimalInfo = new JLabel("CoreID: (none) | 0 reaches")

// Buttons

@Field def btnPrevAnimal = new JButton("▲ Prev Animal")
@Field def btnNextAnimal = new JButton("▼ Next Animal")
@Field def btnCloseVideos = new JButton("Close Videos")

// Animal nav panel
def animalNavPanel = new JPanel(new FlowLayout(FlowLayout.LEFT))
animalNavPanel.setBorder(BorderFactory.createTitledBorder("Animal Navigation"))
@Field def btnExportSnippet = new JButton("Export Snippet")

animalNavPanel.add(btnPrevAnimal)
animalNavPanel.add(btnNextAnimal)
animalNavPanel.add(btnCloseVideos)
animalNavPanel.add(btnExportSnippet)
animalNavPanel.add(lblAnimalInfo)
frame.add(animalNavPanel)

// Preselect row 0 if animals exist
if (animals && animals.size() > 0) {
    tblAnimals.setRowSelectionInterval(0, 0)
    def selected = animals[0]
    lblAnimalInfo.setText("CoreID: ${selected.coreID} | Reaches: ${selected.nReaches}")
}

// --- Reach navigation ---
def reachPanel = new JPanel(new FlowLayout(FlowLayout.LEFT))
reachPanel.setBorder(BorderFactory.createTitledBorder("Reach Navigation"))
@Field def btnStart = new JButton("Load Reach")
def btnNextReach = new JButton("► Next Reach [n]")
def btnPrevReach = new JButton("◄ Prev Reach [p]")
@Field def btnJumpUnlabeled = new JButton("⏩ First Unlabeled")

def txtReachIndex = new JTextField("1", 3)
@Field def lblReachInfo = new JLabel("Reach 0 / 0")
reachPanel.add(new JLabel("Reach #:"))
reachPanel.add(txtReachIndex)
reachPanel.add(btnStart)
reachPanel.add(btnPrevReach)
reachPanel.add(btnNextReach)
reachPanel.add(btnJumpUnlabeled)
reachPanel.add(lblReachInfo)
frame.add(reachPanel)

btnModeSwitch.addActionListener {
    useManualAlignment = !useManualAlignment
    if (useManualAlignment) {
        btnModeSwitch.setText("Switch to Auto [s]")
        IJ.log("🔧 Alignment mode switched to MANUAL for all reaches")
    } else {
        btnModeSwitch.setText("Switch to Manual [s]")
        IJ.log("🤖 Alignment mode switched to AUTO for all reaches")
    }

    // Reload current reach with new mode
    if (reachIndex >= 0 && reachIndex < reaches.size()) {
        loadReach(reachIndex)
    }
}

// --- Playback controls (left side) ---
def playControls = new JPanel(new FlowLayout(FlowLayout.LEFT))
playControls.setBorder(BorderFactory.createTitledBorder("Playback"))

@Field def btnPlay = new JButton("▶ Play")
@Field def btnPause = new JButton("⏸ Pause")
@Field def txtFps = new JTextField("150", 3)  // default FPS = 150

playControls.add(btnPlay)
playControls.add(btnPause)
playControls.add(new JLabel("Speed (fps):"))
playControls.add(txtFps)


// --- Offset controls (right side) ---
def offsetControls = new JPanel(new FlowLayout(FlowLayout.LEFT))
offsetControls.setBorder(BorderFactory.createTitledBorder("Alignment Offset"))

@Field def btnModeSwitch = new JButton("Switch to Manual")
def btnAlignPlay = new JButton("Align & Play [a]")

@Field def btnNudgeM1 = new JButton("⏪ -10")
@Field def btnNudgeP1 = new JButton("⏩ +10")
@Field def btnNudgeM5 = new JButton("⏪ -50")
@Field def btnNudgeP5 = new JButton("⏩ +50")


offsetControls.add(btnModeSwitch)
offsetControls.add(btnAlignPlay)
offsetControls.add(lblOffset)
offsetControls.add(btnNudgeM5)
offsetControls.add(btnNudgeM1)
offsetControls.add(btnNudgeP1)
offsetControls.add(btnNudgeP5)


// --- Combine them with 30/70 split ---
def playPanel = new JPanel(new GridBagLayout())
def gbc = new GridBagConstraints()
gbc.fill = GridBagConstraints.HORIZONTAL
gbc.weighty = 1.0

// playback controls = 30%
gbc.gridx = 0
gbc.weightx = 0.3
playPanel.add(playControls, gbc)

// offset controls = 70%
gbc.gridx = 1
gbc.weightx = 0.7
playPanel.add(offsetControls, gbc)

frame.add(playPanel)


// --- Classification panel ---
def classOuter = new JPanel()
classOuter.setLayout(new BorderLayout())
classOuter.setBorder(BorderFactory.createTitledBorder("Classification"))

// Status label at the TOP
@Field def lblStatus = new JLabel("Status: Ready", SwingConstants.CENTER)
lblStatus.setFont(new Font("Arial", Font.BOLD, 16))
lblStatus.setBorder(BorderFactory.createLineBorder(Color.LIGHT_GRAY, 1))
classOuter.add(lblStatus, BorderLayout.NORTH)

// Buttons in a 2x5 grid, grouped by category
def classPanel = new JPanel(new GridLayout(2,5,10,10))
@Field def btnClass = [:]

// Colors by category
def pastelGreen  = new Color(144, 238, 144)  // success
def pastelRed    = new Color(255, 160, 122)  // errors
def pastelOrange = new Color(255, 200, 120)  // misses
def pastelYellow = new Color(255, 239, 170)  // attempts
def pastelGray   = new Color(211, 211, 211)  // neutral gray for skip
def pastelBlue   = new Color(173, 216, 230)  // soft blue for unknown

// Helper to build button
def mkBtn = { String cleanLabel, Color bg, int key ->
    def b = new JButton("${cleanLabel} [${key}]")
    b.putClientProperty("cleanLabel", cleanLabel)
    b.setBackground(bg)
    b.setOpaque(true)
    b.setBorder(BorderFactory.createLineBorder(Color.LIGHT_GRAY, 1))
    b.setPreferredSize(new Dimension(220, 40))
    btnClass[cleanLabel] = b
    return b
}

// Column 1: Successes
classPanel.add(mkBtn("Success",                 pastelGreen, 1))
classPanel.add(mkBtn("Success After Many",      pastelGreen, 2))

// Column 2: Errors
classPanel.add(mkBtn("Error – During Grasp",    pastelOrange, 3))
classPanel.add(mkBtn("Error – Retrieve Failure",pastelOrange, 4))

// Column 3: Misses
classPanel.add(mkBtn("Miss – Knock",            pastelYellow, 5))
classPanel.add(mkBtn("Miss – Targeting",        pastelYellow, 6))

// Column 4: Attempts
classPanel.add(mkBtn("Attempt – No Touch",      pastelRed, 7))
classPanel.add(mkBtn("Attempt – No Pellet",     pastelRed, 8))

// Column 5: skips
classPanel.add(mkBtn("Skip (Not a Reach)",      pastelGray, 9))
classPanel.add(mkBtn("Unknown / Hard to Say",   pastelBlue, 0))

classOuter.add(classPanel, BorderLayout.CENTER)
frame.add(classOuter)

def labelMap = [
    1:"Success",
    2:"Success After Many",
    3:"Error – During Grasp",
    4:"Error – Retrieve Failure",
    5:"Miss – Knock",
    6:"Miss – Targeting",
    7:"Attempt – No Touch",
    8:"Attempt – No Pellet",
    9:"Skip (Not a Reach)",
    0:"Unknown / Hard to Say"
]

// Final frame setup
frame.setSize(1000, 650)
frame.setVisible(true)
frame.setLocation(400, 600)

import java.awt.KeyEventDispatcher
import java.awt.KeyboardFocusManager
import java.awt.event.KeyEvent

KeyboardFocusManager.currentKeyboardFocusManager.addKeyEventDispatcher(
    new KeyEventDispatcher() {
        @Override
        boolean dispatchKeyEvent(KeyEvent e) {
            if (e.getID() == KeyEvent.KEY_PRESSED) {
                // 👉 Don't steal numbers if a text field has focus
                def focusOwner = KeyboardFocusManager.currentKeyboardFocusManager.focusOwner
                if (focusOwner instanceof JTextField) {
                    return false
                }

                switch (e.getKeyCode()) {
                    case KeyEvent.VK_0:
                    case KeyEvent.VK_1..KeyEvent.VK_9:
                        def idx = (e.getKeyCode() == KeyEvent.VK_0) ? 0 : (e.getKeyCode() - KeyEvent.VK_0)
                        if (labelMap.containsKey(idx)) {
                            def lbl = labelMap[idx]
                            classifyReach(lbl)
                        }
                        return true

                    case KeyEvent.VK_N:
                        if (reachIndex < reaches.size() - 1) {
                            reachIndex++
                            loadReach(reachIndex)
                        }
                        return true

                    case KeyEvent.VK_P:
                        if (reachIndex > 0) {
                            reachIndex--
                            loadReach(reachIndex)
                        }
                        return true

                    case KeyEvent.VK_A:
                        btnAlignPlay.doClick()
                        return true

                    case KeyEvent.VK_S:
                        btnModeSwitch.doClick()
                        return true

                    case KeyEvent.VK_SPACE:
                        if (playing) {
                            btnPause.doClick()   // pause if already playing
                        } else {
                            btnPlay.doClick()    // play if stopped
                        }
                        return true

                }
            }
            return false
        }
    }
)

// --- Helpers (stubs) ---
def openAnimal(selectedCoreID, startReach) {
    if (playTimer) { playTimer.cancel(); playing = false }

    // 🔒 Close old videos if they exist
    if (impFront) { impFront.close(); impFront = null }
    if (impSide)  { impSide.close();  impSide  = null }

    // 🔒 Skip excluded animals
    if (excluded.contains(selectedCoreID)) {
        IJ.showMessage("Excluded Animal",
            "The animal with CoreID '${selectedCoreID}' is marked as excluded.\n" +
            "Use MATLAB to uncheck it if you want to include it again.")
        lblAnimalInfo.setText("CoreID: ${selectedCoreID} | ❌ Excluded")
        return
    }

    def idx = animals.findIndexOf { it.coreID == selectedCoreID }
    fileIndex = idx

    def a = animals[idx]
    coreID = a.coreID
    currentFrontFile = a.frontFile
    currentSideFile  = a.sideFile
    if (!currentFrontFile || !currentSideFile) {
        IJ.error("Missing video(s) for ${coreID}")
        return
    }

    // Load reaches from MAT
    reaches = loadReachesMat(coreID)
    if (reaches.isEmpty()) {
        IJ.error("No reaches found in MAT for ${coreID}")
        return
    }

    // Refresh labeled count from CSV
    def labelsMap = loadLabelsFromCSV(coreID)
    def nLabeledNow = labelsMap.size()

    // Update animals list and table model
    def row = animals.findIndexOf { it.coreID == coreID }
    if (row >= 0) {
        animals[row].nLabeled = nLabeledNow
        model.setValueAt(nLabeledNow, row, 3)  // column 3 = "Labeled"
    }

   // get video length map directly from full opens
videoLengths = [:]

// Open full videos once (virtual stacks)
impSide  = openFullVideo(currentSideFile)
impFront = openFullVideo(currentFrontFile)
if (!impSide || !impFront) {
    IJ.error("Failed to open full videos for ${coreID}")
    return
}


// record lengths directly
videoLengths[currentSideFile]  = Math.max(impSide.getNFrames(),  impSide.getStackSize())
videoLengths[currentFrontFile] = Math.max(impFront.getNFrames(), impFront.getStackSize())


// Tile on first open
IJ.run("Tile")

// Start at requested reach (default 1 handled earlier)
reachIndex = Math.max(0, Math.min(startReach-1, reaches.size()-1))
updateLabels()
loadReach(reachIndex)

}

def openFullVideo(File videoFile) {
    def opts = "choose=${videoFile.absolutePath} use_virtual_stack first_frame=1 last_frame=999999 step=1"
    IJ.run("Movie (FFMPEG)...", opts)
    def imp = WindowManager.getCurrentImage()
    if (!imp) {
        IJ.log("⚠️ Could not open ${videoFile.name}")
        return null
    }
    return imp
}


def clampRange(int start, int end, int maxFrames) {
    int s = Math.max(1, start)
    int e = Math.min(end, maxFrames)
    if (e < s) e = s
    return [s, e]
}

def setPlaybackWindow(int sStartTrue, int sEndTrue, int fStartTrue, int fEndTrue) {
    int sideMax  = videoLengths[currentSideFile]  ?: 0
    int frontMax = videoLengths[currentFrontFile] ?: 0

    // 🔹 Expand with buffer here
    int sStart = Math.max(1, sStartTrue - buffer)
    int sEnd   = sEndTrue + (buffer*2)
    int fStart = Math.max(1, fStartTrue - buffer)
    int fEnd   = fEndTrue + (buffer*2)

    // Clamp to video bounds
    def (ss, se) = clampRange(sStart, sEnd, sideMax)
    def (fs, fe) = clampRange(fStart, fEnd, frontMax)

    playStartSide  = ss
    playEndSide    = se
    playStartFront = fs
    playEndFront   = fe

    // Track aligned *true* ranges (without buffer) for overlay color logic
    alignedSideStart  = sStartTrue
    alignedSideEnd    = sEndTrue
    alignedFrontStart = fStartTrue
    alignedFrontEnd   = fEndTrue

    // Playback length = shorter of the two buffered windows
    playLen = Math.min(playEndSide - playStartSide + 1,
                       playEndFront - playStartFront + 1)

    if (playLen <= 0) {
        //IJ.log("⚠️ Empty playback window (Side ${ss}-${se}, Front ${fs}-${fe})")
        playLen = 0
    }

    // Initialize views
    SwingUtilities.invokeLater {
    if (impSide)  impSide.setSlice(playStartSide)
    if (impFront) impFront.setSlice(playStartFront)

    // Update overlays with true reach boundaries
    if (impSide)  updateOverlayBlock(impSide, alignedSideStart, alignedSideEnd, "side", lastReachFlag)
    if (impFront) updateOverlayBlock(impFront, alignedFrontStart, alignedFrontEnd, "front", lastReachFlag)
    }
}

def lockOffsetFromCurrentSlices() {
    if (!impSide || !impFront) return

    int sStartTrue = alignedSideStart
    int sEndTrue   = alignedSideEnd

    int sideSlice  = impSide.getCurrentSlice()
    int frontSlice = impFront.getCurrentSlice()
    currentOffset  = frontSlice - sideSlice
    lblOffset.setText("Offset: " + currentOffset)

    // Compare with slope expectation at the *true* start
    def al = alignmentMap[coreID]
    boolean haveSlope = (al && al.sideFrame1 != null && al.sideFrame2 != null &&
                         al.offStart   != null && al.offEnd   != null &&
                         al.sideFrame2 != al.sideFrame1)
    if (haveSlope) {
        double slope     = (al.offEnd - al.offStart) / (double)(al.sideFrame2 - al.sideFrame1)
        double intercept = al.offStart - slope * al.sideFrame1
        int expectedAtStart = (int)Math.round(slope * sStartTrue + intercept)
    } 

    int fStartTrue = sStartTrue + currentOffset
    int fEndTrue   = sEndTrue   + currentOffset
    setPlaybackWindow(sStartTrue, sEndTrue, fStartTrue, fEndTrue)
}


def applyOffset(int newOffset) {
    if (!impSide || !impFront) return
    currentOffset = newOffset
    lblOffset.setText("Offset: " + currentOffset)

    int sStartTrue = alignedSideStart
    int sEndTrue   = alignedSideEnd

    int fStartTrue = sStartTrue + currentOffset
    int fEndTrue   = sEndTrue   + currentOffset

    impFront.setSlice(Math.max(1, fStartTrue))
    setPlaybackWindow(sStartTrue, sEndTrue, fStartTrue, fEndTrue)
}

import ij.gui.OvalRoi

def updateOverlayBlock(imp, int realStart, int realEnd, String tag, boolean isLast=false) {
    if (!imp) return
    def ov = new Overlay()
    int curSlice = imp.getCurrentSlice()

    boolean inWindow = (tag == "side") ?
        (curSlice >= playStartSide && curSlice <= playEndSide) :
        (curSlice >= playStartFront && curSlice <= playEndFront)

    if (inWindow) {
       Color col
        if (curSlice >= realStart && curSlice <= realEnd) {
            // Inside the true reach
            col = new Color(220, 50, 50, 180)    // 🔴 red
        } else if (curSlice < realStart) {
            // Pre-reach buffer
            col = new Color(80, 120, 200, 180)   // 🔵 blue
        } else {
            // Post-reach buffer
            col = new Color(160, 80, 200, 180)  // pruple (or any other debug color)
        }

        // main dot
        int boxSize = 25
        int x = imp.getWidth() - boxSize - 5
        int y = 5
        def roi = new OvalRoi(x, y, boxSize, boxSize)
        roi.setFillColor(col)
        roi.setStrokeColor(col)
        ov.add(roi)

        // add extra marker if last reach
        if (isLast) {
            def roi2 = new OvalRoi(x, y + boxSize + 5, boxSize, boxSize)
            roi2.setFillColor(Color.GRAY)   // solid black fill
            roi2.setStrokeColor(Color.BLACK) // black border
            ov.add(roi2)
        }
    }

    imp.setOverlay(ov)
    imp.updateAndDraw()
}

def computeManualFrontWindow(int sStartTrue, int sEndTrue) {
    // CSV override ONLY if this reach is already labeled
    def labelsMap = loadLabelsFromCSV(coreID)
    def saved = labelsMap[reachIndex+1]  // map: [label: ..., offset: ...]
    Integer csvOffset = (saved && saved.label && saved.label.trim()) ? (saved.offset as Integer) : null

    // Alignment slope (if available)
    def al = alignmentMap[coreID]
    boolean haveSlope = (al && al.sideFrame1 != null && al.sideFrame2 != null &&
                         al.offStart   != null && al.offEnd   != null &&
                         al.sideFrame2 != al.sideFrame1)
    double slope = 0d, intercept = 0d
    Integer expectedFromSlopeAtStart = null
    if (haveSlope) {
        slope     = (al.offEnd - al.offStart) / (double)(al.sideFrame2 - al.sideFrame1)
        intercept = al.offStart - slope * al.sideFrame1
        expectedFromSlopeAtStart = (int)Math.round(slope * sStartTrue + intercept)
    }

    int usedOffset
    String reason

    if (csvOffset != null) {
        // This reach is explicitly labeled
        usedOffset = csvOffset
        reason = "CSV (labeled) override"
    } else {
        def prev = labelsMap[reachIndex] // previous reach = N in map if current is N+1
        if (prev && prev.offset != null && haveSlope) {
            // Propagate previous offset forward using slope
            int deltaSide = sStartTrue - (reaches[reachIndex-1]?.sideFrames?.max() ?: sStartTrue)
            usedOffset = prev.offset + (int)Math.round(slope * deltaSide)
            reason = "propagated from previous labeled reach (with slope adjustment)"
        } else if (haveSlope) {
            usedOffset = expectedFromSlopeAtStart
            reason = "alignment slope"
        } else {
            usedOffset = 0
            reason = "fallback 0"
        }
    }

    int fStartTrue = sStartTrue + usedOffset
    int fEndTrue   = sEndTrue   + usedOffset
    return [fStartTrue, fEndTrue, usedOffset]
}


def reachesTooClose(r1, r2, int margin=10) {
    // Use sideFrames as canonical
    def s1 = (r1.sideFrames && !r1.sideFrames.isEmpty()) ? [r1.sideFrames.min(), r1.sideFrames.max()] : [0,0]
    def s2 = (r2.sideFrames && !r2.sideFrames.isEmpty()) ? [r2.sideFrames.min(), r2.sideFrames.max()] : [0,0]

    int end1 = s1[1]
    int start2 = s2[0]

    return (start2 - end1) <= margin
}

def loadReach(rIdx) {
    if (rIdx < 0 || rIdx >= reaches.size()) return
    def r = reaches[rIdx]
    lastReachFlag = (rIdx == reaches.size() - 1)
    
    if (rIdx > 0) {
        def prev = reaches[rIdx - 1]
        if (reachesTooClose(prev, r, 15)) {
            IJ.log("⚠ Reach ${rIdx+1} starts within 15 frames of Reach ${rIdx}, may be part of same event.")
        }
    }

    // --- Side true reach frames ---
    def sideStartTrue = r.sideFrames ? r.sideFrames.min() : 0
    def sideEndTrue   = r.sideFrames ? r.sideFrames.max() : 0

    // --- Front true reach frames (raw, from MAT) ---
    def fStartTrueRaw = r.frontFrames ? r.frontFrames.min() : 1
    def fEndTrueRaw   = r.frontFrames ? r.frontFrames.max() : 1

    sideStartTrue = Math.max(1, Math.min(sideStartTrue, videoLengths[currentSideFile]))
    sideEndTrue   = Math.max(1, Math.min(sideEndTrue, videoLengths[currentSideFile]))

    fStartTrueRaw = Math.max(1, Math.min(fStartTrueRaw, videoLengths[currentFrontFile]))
    fEndTrueRaw   = Math.max(1, Math.min(fEndTrueRaw, videoLengths[currentFrontFile]))

    if (sideEndTrue > videoLengths[currentSideFile]) {
        IJ.log("⚠️ Side reach frames exceed side video length: requested ${sideEndTrue}, max=${videoLengths[currentSideFile]}")
    }


    int alignedFStart, alignedFEnd

    if (useManualAlignment) {
        // Manual: compute aligned front window + offset
        def (manualFs, manualFe, manualOffset) = computeManualFrontWindow(sideStartTrue, sideEndTrue)
        currentOffset  = manualOffset
        alignedFStart  = manualFs
        alignedFEnd    = manualFe
    } else {
        // Auto: raw offset between side/front starts
        currentOffset  = fStartTrueRaw - sideStartTrue
        alignedFStart  = fStartTrueRaw
        alignedFEnd    = fEndTrueRaw
    }

    alignedFStart = Math.max(1, Math.min(alignedFStart, videoLengths[currentFrontFile]))
    alignedFEnd   = Math.max(1, Math.min(alignedFEnd,   videoLengths[currentFrontFile]))


    // 🔹 Build full buffered window
    setPlaybackWindow(sideStartTrue, sideEndTrue, alignedFStart, alignedFEnd)

    if (playLen <= 0) {
        IJ.log("⏭ Skipping reach ${rIdx+1}: invalid playback window")
        classifyReach("Skip (Not a Reach)")
        return
    }

    lblReachInfo.setText("Reach ${rIdx+1} / ${reaches.size()}")

    def labelsMap = loadLabelsFromCSV(coreID)
    def labelFromCsv = labelsMap[rIdx+1]
    def lblTxt = labelFromCsv ?
        "Reach ${rIdx+1} | s[${sideStartTrue}-${sideEndTrue}] | ${labelFromCsv}" :
        (r.label?.trim() ?
            "Reach ${rIdx+1} | s[${sideStartTrue}-${sideEndTrue}] | ${r.label}" :
            "Reach ${rIdx+1} | s[${sideStartTrue}-${sideEndTrue}] | unlabeled")
    lblStatus.setText(lblTxt)

    loopCount[0] = 0
    SwingUtilities.invokeLater {
    if (impSide)  impSide.setSlice(playStartSide)
    if (impFront) impFront.setSlice(playStartFront)
    }

    // 🔹 Reset playback counters
    tickK = 0
    tickLoop = 0

    // IJ.log("loadReach ${rIdx+1} | sideCur=${impSide?.getCurrentSlice()} " +
    //        "frontCur=${impFront?.getCurrentSlice()} " +
    //        "playSide=[${playStartSide}-${playStartSide+playLen}] " +
    //        "playFront=[${playStartFront}-${playStartFront+playLen}] " +
    //        "offset=${currentOffset}")

    // 🔹 Autoplay trigger
    autoPlayFlag = true
    SwingUtilities.invokeLater {
        btnPlay.doClick()
    }
}

def classifyReach(label, boolean autoSkip=false) {
    if (!impSide || !impFront) {
        IJ.log("⚠️ classifyReach ignored: no videos open")
        return
    }

    if (reaches == null || reachIndex < 0 || reachIndex >= reaches.size()) {
        lblStatus.setText("⚠️ No reach loaded to classify")
        return
    }
    
    def r = reaches[reachIndex]
    def cleanLabel = btnClass[label]?.getClientProperty("cleanLabel") ?: label
    r.label = cleanLabel

    // Prepare CSV
    def outDir = new File(dir, "OUT")
    if (!outDir.exists()) outDir.mkdirs()
    def csvFile = new File(outDir, "${coreID}_reachLabels.csv")

    def header = "CoreID,ReachIndex,SideStart,SideEnd,FrontStart,FrontEnd,Offset,Label"
    if (!csvFile.exists()) {
        csvFile.text = header + "\n"
    }

      // Read existing lines but ignore any old 7-col header
    def lines = csvFile.readLines()
    def body = (lines.size() > 1) ? lines[1..-1] : []

    // Parse existing rows flexibly (7 or 8 cols) into a map
    def existingMap = [:]
    body.each { line ->
        def parts = line.split(",")
        if (parts.size() >= 7) {
            def rIdx = parts[1].trim().toInteger()
            def lab  = (parts.size() >= 8) ? parts[7].trim() : parts[6].trim()
            existingMap[rIdx] = lab
        }
    }

    // Build new row in 8-column format
    def sideStart  = alignedSideStart
    def sideEnd    = alignedSideEnd
    def frontStart = alignedFrontStart
    def frontEnd   = alignedFrontEnd
    def newRow = "${coreID},${reachIndex+1},${sideStart},${sideEnd},${frontStart},${frontEnd},${currentOffset},${cleanLabel}"

    // Replace or add
    existingMap[reachIndex+1] = cleanLabel
    def updatedBody = body.findAll { !it.startsWith("${coreID},${reachIndex+1},") }
    updatedBody << newRow

    try {
        csvFile.text = ([header] + updatedBody).join("\n") + "\n"
    } catch (IOException e) {
        IJ.log("❌ Oops: cannot write ${csvFile.name}. " +
               "Is it open in Excel? Please close it and try again.")
        return  // optional: skip updating instead of crashing
    }

    // Update UI counts
    def labelsMap = loadLabelsFromCSV(coreID)
    def nLabeledNow = labelsMap.size()

    def row = animals.findIndexOf { it.coreID == coreID }
    if (row >= 0) {
        animals[row].nLabeled = nLabeledNow
        model.setValueAt(nLabeledNow, row, 3)    // triggers the progress bar renderer
    }
    
    IJ.log("Reach ${reachIndex+1} | s[${sideStart}-${sideEnd}] | ${cleanLabel} | offset: ${currentOffset}")
    lblStatus.setText("Reach ${reachIndex+1}: '${cleanLabel}'")

    // Auto-advance
    if (!autoSkip && reachIndex < reaches.size() - 1) {
        reachIndex++
        SwingUtilities.invokeLater { loadReach(reachIndex) }
    }
}

def updateLabels() {
    lblAnimalInfo.setText("CoreID: ${coreID} | Reach ${reachIndex+1} / ${reaches.size()}")
}

// --- Utility ---
def getBaseName(fname) {
    def b = fname
    if (b.toLowerCase().endsWith(".mp4")) b = b[0..-5]
    b = b.replace("_Front","").replace("_Side","")
    return b
}

def loadLabelsFromCSV(coreID) {
    def csvFile = new File(new File(dir, "OUT"), "${coreID}_reachLabels.csv")
    if (!csvFile.exists()) return [:]
    def map = [:]
    csvFile.eachLine { line, idx ->
        if (idx == 0) return // skip header
        def parts = line.split(",")
        try {
            if (parts.size() >= 8) {
                // New format: has Offset + Label
                def rIdx   = parts[1].trim().toInteger()
                def offset = parts[6].trim().isInteger() ? parts[6].trim().toInteger() : 0
                def lab    = parts[7].trim()
                map[rIdx] = [label: lab, offset: offset]
            } else if (parts.size() >= 7) {
                // Old format: no Offset column → set offset = 0
                def rIdx   = parts[1].trim().toInteger()
                def lab    = parts[6].trim()
                map[rIdx] = [label: lab, offset: 0]
            }
        } catch (Exception ignored) {
            // skip malformed lines gracefully
        }
    }
    return map
}



def reachesOverlap(r1, r2, int buffer=0) {
    // Use side frames as the canonical definition
    def s1 = (r1.sideFrames && !r1.sideFrames.isEmpty()) ? [r1.sideFrames.min(), r1.sideFrames.max()] : [0,0]
    def s2 = (r2.sideFrames && !r2.sideFrames.isEmpty()) ? [r2.sideFrames.min(), r2.sideFrames.max()] : [0,0]

    // Expand with buffer if you want to check buffered windows
    int start1 = Math.max(1, s1[0] - buffer)
    int end1   = s1[1] + buffer
    int start2 = Math.max(1, s2[0] - buffer)
    int end2   = s2[1] + buffer

    // Overlap if ranges intersect
    return !(end1 < start2 || end2 < start1)
}


// --- Listeners ---
tblAnimals.getSelectionModel().addListSelectionListener(
    new javax.swing.event.ListSelectionListener() {
        @Override
        void valueChanged(javax.swing.event.ListSelectionEvent e) {
            if (!e.getValueIsAdjusting()) {
                def row = tblAnimals.getSelectedRow()
                if (row >= 0) {
                    def selected = animals[row]
                    lblAnimalInfo.setText("CoreID: ${selected.coreID} | Reaches: ${selected.nReaches}")
                }
            }
        }
    }
)

tblAnimals.addMouseListener(new java.awt.event.MouseAdapter() {
    @Override
    void mouseClicked(java.awt.event.MouseEvent e) {
        if (e.clickCount == 2) {
            int viewRow = tblAnimals.getSelectedRow()
            if (viewRow >= 0) {
                int modelRow = tblAnimals.convertRowIndexToModel(viewRow)
                def selected = animals[modelRow]
                def startIdx = 1
                try { startIdx = txtReachIndex.text.toInteger() } catch (ignored) {}
                openAnimal(selected.coreID, startIdx)
            }
        }
    }
})


// Progress bar for column 3 ("Labeled")
tblAnimals.getColumnModel().getColumn(3).setCellRenderer(new javax.swing.table.TableCellRenderer() {
    @Override
    Component getTableCellRendererComponent(JTable table, Object value,
                                            boolean isSelected, boolean hasFocus,
                                            int row, int column) {
        // convert view row → model row
        int modelRow = table.convertRowIndexToModel(row)
        def animal   = animals[modelRow]
        
        // Coerce totals & labeled to ints safely
        int total   = (animals[row]?.nReaches instanceof Number) ? ((Number) animals[row].nReaches).intValue() : 0
        int labeled = (value        instanceof Number) ? ((Number) value).intValue() : 0

        // Make sure ranges are sane
        total   = Math.max(0, total)
        labeled = Math.max(0, Math.min(labeled, total))

        // Use max >= 1 so the bar can render even when total == 0
        JProgressBar pb = new JProgressBar(0, Math.max(1, total))
        pb.setValue(labeled)
        pb.setBackground(Color.WHITE)

        // Percent text (safe for total == 0)
        int pct = (total > 0) ? (int) Math.round(labeled * 100.0d / total) : 0
        pb.setStringPainted(true) //delete for no text
        pb.setString(String.format("%d%%", pct)) //delete for no text


        if (excluded.contains(animal.coreID)) {
            pb.setBackground(Color.LIGHT_GRAY)
        } else {
            pb.setBackground(Color.WHITE)
        }

        return pb
    }
})


btnJumpUnlabeled.addActionListener({
    if (reaches && !reaches.isEmpty()) {
        def labelsMap = loadLabelsFromCSV(coreID)
        // Find the first reach index (0-based) that isn’t in the CSV map
        def targetIdx = (0..<reaches.size()).find { !(labelsMap.containsKey(it+1)) }
        if (targetIdx != null) {
            reachIndex = targetIdx
            loadReach(reachIndex)
            IJ.log("→ Jumped to first unlabeled reach: ${reachIndex+1}")
        } else {
            IJ.log("✔ All reaches labeled for ${coreID}")
            lblStatus.setText("All reaches labeled!")
        }
    }
})


btnStart.addActionListener({
    int viewRow = tblAnimals.getSelectedRow()
    if (viewRow < 0) return
    int modelRow = tblAnimals.convertRowIndexToModel(viewRow)
    def selected = animals[modelRow]
    def startIdx = 1
    try { startIdx = txtReachIndex.text.toInteger() } catch(e) {}
    openAnimal(selected.coreID, startIdx)
})


btnNextAnimal.addActionListener({
    def row = tblAnimals.getSelectedRow()
    if (row < animals.size() - 1) {
        tblAnimals.setRowSelectionInterval(row + 1, row + 1)
    }
})

btnPrevAnimal.addActionListener({
    def row = tblAnimals.getSelectedRow()
    if (row > 0) {
        tblAnimals.setRowSelectionInterval(row - 1, row - 1)
    }
})

btnNextReach.addActionListener({
    if (reachIndex < reaches.size() - 1) {
        reachIndex++
        loadReach(reachIndex)
        frame.requestFocusInWindow()   // <- Add this to regain focus
    }
})

btnPrevReach.addActionListener({
    if (reachIndex > 0) {
        reachIndex--
        loadReach(reachIndex)
        frame.requestFocusInWindow()   // <- Add this too
    }
})

def stopPlayback() {
    if (playTimer != null) {
        playTimer.cancel()
        playTimer = null
    }
    playing = false
}

btnPlay.addActionListener({
    if (!impFront || !impSide) return
    if (playing) return
    if (playLen <= 0) {
        IJ.log("⚠️ Nothing to play: empty play window")
        return
    }

    if (!autoPlayFlag) {
        // only relock if this is user-triggered
        lockOffsetFromCurrentSlices()
    }
    autoPlayFlag = false  // reset

    // force start at beginning of window
    SwingUtilities.invokeLater {
    if (impSide)  impSide.setSlice(playStartSide)
    if (impFront) impFront.setSlice(playStartFront)
    }

    // Capture manual scroll as new offset + rebuild window (still OK)
    lockOffsetFromCurrentSlices()

    int fps   = Math.max(1, (txtFps.text as int))
    int delay = (int)(1000.0 / fps)

    // Reset playback counters
    tickK = 0
    tickLoop = 0

    // Stop any existing playback timer
    stopPlayback()

    // Fresh java.util.Timer
    playTimer = new java.util.Timer("playback", true)
    playTimer.scheduleAtFixedRate(new TimerTask() {
        @Override
        void run() {
            if (!impSide || !impFront) {
                stopPlayback()
                return
            }

            if (tickK >= playLen) {
                tickK = 0
                tickLoop++
                if (impSide) impSide.setSlice(playStartSide)
                if (impFront) impFront.setSlice(playStartFront)
                // IJ.log("loop-reset #${tickLoop} | sideCur=${impSide?.getCurrentSlice()} " +
                //        "frontCur=${impFront?.getCurrentSlice()} " +
                //        "playSide=[${playStartSide}-${playStartSide+playLen}] " +
                //        "playFront=[${playStartFront}-${playStartFront+playLen}] " +
                //        "offset=${currentOffset}")
            } else {
                impSide.setSlice(playStartSide + tickK)
                impFront.setSlice(playStartFront + tickK)
                if (tickK % fps == 0 || tickK <= 1) {
                    // IJ.log("tick k=${tickK} | sideCur=${impSide?.getCurrentSlice()} " +
                    //        "frontCur=${impFront?.getCurrentSlice()} " +
                    //        "playSide=[${playStartSide}-${playStartSide+playLen}] " +
                    //        "playFront=[${playStartFront}-${playStartFront+playLen}] " +
                    //        "offset=${currentOffset}")
                }
                tickK++
            }

            updateOverlayBlock(impSide, alignedSideStart, alignedSideEnd, "side", lastReachFlag)
            updateOverlayBlock(impFront, alignedFrontStart, alignedFrontEnd, "front", lastReachFlag)
        }
    }, 0, delay)

    playing = true
})

btnAlignPlay.addActionListener({
    if (!impSide || !impFront) return

    def curSide  = impSide.getCurrentSlice()
    def curFront = impFront.getCurrentSlice()

    // new offset from the currently viewed slices
    currentOffset = curFront - curSide
    lblOffset.setText("Offset: " + currentOffset)

    // keep true side reach window
    int sStartTrue = alignedSideStart
    int sEndTrue   = alignedSideEnd

    // recompute front window from side window + offset
    int fStartTrue = sStartTrue + currentOffset
    int fEndTrue   = sEndTrue   + currentOffset

    // now set the buffered playback window around the full reach
    setPlaybackWindow(sStartTrue, sEndTrue, fStartTrue, fEndTrue)

    tickK = 0
    tickLoop = 0

    btnPlay.doClick()
})



btnPause.addActionListener({
    stopPlayback()
})



btnPause.addActionListener({
    stopPlayback()
})

btnCloseVideos.addActionListener({
    stopPlayback()
    if (impSide) { impSide.close(); impSide = null }
    if (impFront) { impFront.close(); impFront = null }
    lblStatus.setText("Closed video windows")
})


btnClass.each { cleanLabel, b ->
    b.addActionListener({
        classifyReach(cleanLabel)
    })
}

btnNudgeM1.addActionListener({ applyOffset(currentOffset - 10) })
btnNudgeP1.addActionListener({ applyOffset(currentOffset + 10) })
btnNudgeM5.addActionListener({ applyOffset(currentOffset - 50) })
btnNudgeP5.addActionListener({ applyOffset(currentOffset + 50) })

frame.setDefaultCloseOperation(JFrame.DO_NOTHING_ON_CLOSE)
frame.addWindowListener(new java.awt.event.WindowAdapter() {
    @Override
    void windowClosing(java.awt.event.WindowEvent e) {
        // stop playback timer
        stopPlayback()

        // close video windows
        if (impSide) { impSide.close(); impSide = null }
        if (impFront) { impFront.close(); impFront = null }

        // close the GUI
        frame.dispose()

        // quit ImageJ completely
        def ij = IJ.getInstance()
        if (ij != null) {
            ij.quit()
        } else {
            System.exit(0) // fallback if IJ instance is null
        }
    }
})


btnExportSnippet.addActionListener({
    if (!impSide || !impFront) {
        IJ.showMessage("No videos open", "Open an animal and reach first.")
        return
    }
    stopPlayback()

    // ---- output folder
    def vidDir = new File(dir, "VID"); vidDir.mkdirs()

    // ---- reach + label
    def reachID  = reachIndex + 1
    def lblMap   = loadLabelsFromCSV(coreID)
    def lblInfo  = lblMap[reachID]?.label ?: reaches[reachIndex]?.label ?: ""
    def lblSafe  = (lblInfo ?: "Unlabeled").replaceAll(/[^A-Za-z0-9_-]+/, "_")
    def coreID2 = coreID.replace("_Flipped", "")

    // ---- helper: duplicate range with ±100 frames; auto-detect Z vs T
    def dupRange = { ImagePlus src, int start, int end ->
        int C = Math.max(1, src.getNChannels())
        int Z = Math.max(1, src.getNSlices())
        int T = Math.max(1, src.getNFrames())
        def dup = new Duplicator()
        ImagePlus sub
        if (T > 1) {
            // frames in T
            int t1 = Math.max(1, start - 50)
            int t2 = Math.min(T, end + 50)
            sub = dup.run(src, 1, C, 1, Z, t1, t2)
        } else {
            // frames in Z
            int z1 = Math.max(1, start - 50)
            int z2 = Math.min(Z, end + 50)
            sub = dup.run(src, 1, C, z1, z2, 1, T)
        }
        if (sub.isHyperStack()) sub = HyperStackConverter.toStack(sub)
        // ensure ≥2 slices for AVI
        if (sub.getStackSize() < 2) {
            sub.getStack().addSlice(sub.getProcessor().duplicate())
            sub.setStack(sub.getTitle(), sub.getStack())
        }
        // ensure RGB (JPEG compressor happy)
        if (sub.getType() != ImagePlus.COLOR_RGB && sub.getType() != ImagePlus.GRAY8) {
            new ImageConverter(sub).convertToRGB()
        }
        return sub
    }

    // ---- make the two substacks from what you're currently playing
    def sideSub  = dupRange(impSide,  playStartSide,  playEndSide)
    def frontSub = dupRange(impFront, playStartFront, playEndFront)

    def sideFile = new File(vidDir, "${coreID2}_Side_R${reachID}-${lblSafe}.avi")
    def frontFile = new File(vidDir, "${coreID2}_Front_R${reachID}-${lblSafe}.avi")
    
    sideSub.show()
    sideSub.getWindow().toFront()
    WindowManager.setCurrentWindow(sideSub.getWindow())
    Thread.sleep(200)

    moviePath = sideFile.getAbsolutePath().replace("\\", "/")
    IJ.run(sideSub, "Export Movie Using FFmpeg...", "frame_rate=60 format=avi encoder=huffyuv custom_encoder=[] save=" + moviePath)
    
    sideSub.close()

    frontSub.show()
    frontSub.getWindow().toFront()
    WindowManager.setCurrentWindow(frontSub.getWindow())
    Thread.sleep(200)

    moviePath = frontFile.getAbsolutePath().replace("\\", "/")
    IJ.run(frontSub, "Export Movie Using FFmpeg...", "frame_rate=60 format=avi encoder=huffyuv custom_encoder=[] save=" + moviePath)

    frontSub.close()
}
)