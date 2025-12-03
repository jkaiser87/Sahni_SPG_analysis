#@ File (label = "Choose main folder", style="directory") dir

import ij.*
import ij.gui.*
import ij.plugin.*
import ij.process.*
import javax.swing.*
import java.awt.*
import java.awt.event.*
import groovy.transform.Field
import java.util.Timer
import java.util.TimerTask
import ij.measure.ResultsTable

// Globals
@Field def impFront
@Field def impSide
@Field def frontFiles
@Field def fileIndex = -1
@Field def currentFrontFile
@Field def currentSideFile
@Field def savedOffset = 0
@Field def playTimer
@Field def playing = false
@Field def scrollOffsets = new JScrollPane()
@Field def tblOffsets
@Field def offsetsModel
@Field def excluded = [] as Set


// GUI
@Field def frame = new JFrame("Video Sync Tool")
frame.setLayout(new BoxLayout(frame.getContentPane(), BoxLayout.Y_AXIS))

// --- Group 1: Navigation ---
def navPanel = new JPanel(new FlowLayout(FlowLayout.LEFT))
navPanel.setBorder(BorderFactory.createTitledBorder("Video Navigation"))
def btnOpen = new JButton("Open")
def btnNext = new JButton("Next Video")
def btnPrev = new JButton("Prev Video")
@Field def lblInfo = new JLabel("CoreID: (none) | 0 / 0") 
def txtOpenIndex = new JTextField("1", 3)  // default to "1"
navPanel.add(new JLabel("Load #:"))
navPanel.add(txtOpenIndex)
navPanel.add(btnOpen)
navPanel.add(btnNext)
navPanel.add(btnPrev)
navPanel.add(lblInfo)

// --- Group 2: Playback ---
def playPanel = new JPanel(new FlowLayout(FlowLayout.LEFT))
playPanel.setBorder(BorderFactory.createTitledBorder("Playback Controls"))
def btnPlay = new JButton("Play")
def btnPause = new JButton("Pause")
def txtFps = new JTextField("200", 3)
playPanel.add(btnPlay)
playPanel.add(btnPause)
playPanel.add(new JLabel("FPS:"))
playPanel.add(txtFps)

// --- Group 3: Offset ---
def offsetPanel = new JPanel(new FlowLayout(FlowLayout.LEFT))
offsetPanel.setBorder(BorderFactory.createTitledBorder("Offset Tools"))
def btnTestOffset = new JButton("Retrieve Current Offset")
def btnApplyOffset = new JButton("Apply Offset to Front")
def btnSaveOffset1 = new JButton("Save Offset at Start")
def btnSaveOffset2 = new JButton("Save Offset at End")
@Field def txtOffset = new JTextField("0", 4)
offsetPanel.add(btnApplyOffset)
offsetPanel.add(btnTestOffset)
offsetPanel.add(btnSaveOffset1)
offsetPanel.add(btnSaveOffset2)
offsetPanel.add(new JLabel("Offset:"))
offsetPanel.add(txtOffset)

// --- Group 3: Offset ---
def matlabPanel = new JPanel(new FlowLayout(FlowLayout.LEFT))
matlabPanel.setBorder(BorderFactory.createTitledBorder("MATLAB"))
def btnBackMatlab = new JButton("Back to MATLAB")
matlabPanel.add(btnBackMatlab)

// --- Assemble frame ---
frame.add(scrollOffsets)  // table placeholder goes first!
frame.add(navPanel)
frame.add(playPanel)
frame.add(offsetPanel)
frame.add(matlabPanel)

frame.setSize(800, 500) 
frame.setLocation(100, 800)
// populate table immediately at startup
loadOffsetsTable()
frame.setVisible(true)

// --- Helpers ---
def loadOffsetsTable() {
    def inFile = new File(new File(dir, "OUT"), "alignment_table.csv")

    // 🔒 Load excluded CoreIDs
    excluded.clear()
    def exFile = new File(new File(dir, "OUT"), "exclude_table.csv")
    if (exFile.exists()) {
        exFile.eachLine { line, i ->
            if (i == 0 || !line) return
            def parts = line.split(",")
            if (parts.size() >= 2 && parts[1].trim() == "1") {
                excluded.add(parts[0].trim())
            }
        }
    }

def rowList = []
if (inFile.exists()) {
    inFile.eachLine { line, i ->
        if (i == 0 || !line || line.startsWith("CoreID")) return
        def parts = line.split("[,\t]")
        if (parts.size() >= 4) {
            def coreID = parts[0].trim()
            def side1 = parts[1].trim()
            def front1 = parts[2].trim()
            def off1 = parts[3].trim()
            def side2 = (parts.size() > 4) ? parts[4].trim() : "0"
            def front2 = (parts.size() > 5) ? parts[5].trim() : "0"
            def off2 = (parts.size() > 6) ? parts[6].trim() : "0"

            def isExcluded = excluded.contains(coreID)

            rowList << [coreID, side1, front1, off1, side2, front2, off2, isExcluded] as Object[]
        }
    }
}

    def colNames = ["CoreID", "SideFrame1", "FrontFrame1", "Offset1",
                    "SideFrame2", "FrontFrame2", "Offset2","Excluded"]

    offsetsModel = new javax.swing.table.DefaultTableModel(colNames as Object[], 0) {
    @Override
    boolean isCellEditable(int r, int c) { false }

    @Override
    Class<?> getColumnClass(int columnIndex) {
        // 👇 render the "Excluded" column (last one) as checkboxes
        return (columnIndex == 7) ? Boolean.class : Object.class
        }
    }
    rowList.each { row -> offsetsModel.addRow(row as Object[]) }

    tblOffsets = new JTable(offsetsModel)
    tblOffsets.setSelectionMode(ListSelectionModel.SINGLE_SELECTION)
    tblOffsets.setFillsViewportHeight(true)
    tblOffsets.setPreferredScrollableViewportSize(new Dimension(750, 200))

    // ✅ set column widths
    def colModel = tblOffsets.getColumnModel()
    colModel.getColumn(0).setPreferredWidth(150)  // CoreID
    colModel.getColumn(1).setPreferredWidth(80)   // SideFrame1
    colModel.getColumn(2).setPreferredWidth(80)   // FrontFrame1
    colModel.getColumn(3).setPreferredWidth(60)   // Offset1
    colModel.getColumn(4).setPreferredWidth(80)   // SideFrame2
    colModel.getColumn(5).setPreferredWidth(80)   // FrontFrame2
    colModel.getColumn(6).setPreferredWidth(60)   // Offset2

    // put the table into the reserved scroll pane
    scrollOffsets.setViewportView(tblOffsets)
    
    tblOffsets.addMouseListener(new java.awt.event.MouseAdapter() {
        @Override
        void mouseClicked(java.awt.event.MouseEvent e) {
            if (e.clickCount == 2) {
                int viewRow = tblOffsets.getSelectedRow()
                if (viewRow >= 0) {
                    int modelRow = tblOffsets.convertRowIndexToModel(viewRow)

                    def rawID  = offsetsModel.getValueAt(modelRow, 0).toString()
                    def coreID = getBaseName(rawID)

                    def frontFile = findVideoByCoreAndTag(new File(dir, "Front"), coreID, "Front")
                    def sideFile  = findVideoByCoreAndTag(new File(dir, "Side"),  coreID, "Side")

                    if (frontFile && sideFile) {
                        openPair(frontFile, sideFile)
                    } else {
                        IJ.error("Missing Front/Side video for " + coreID)
                    }
                }
            }
        }
    })



    frame.revalidate()
    frame.repaint()
    }


def saveOffsetsTableToCSV() {
    if (!offsetsModel) {
        IJ.log("⚠️ No offsets table model available to save.")
        return
    }

    def outDir = new File(dir, "OUT")
    if (!outDir.exists()) outDir.mkdirs()
    def outFile = new File(outDir, "alignment_table.csv")

    def writer = new FileWriter(outFile, false) // overwrite
    writer.write("CoreID,SideFrame1,FrontFrame1,Offset1,SideFrame2,FrontFrame2,Offset2\n")

    for (int row = 0; row < offsetsModel.getRowCount(); row++) {
        def values = []
        for (int col = 0; col < 7; col++) {   // only first 7 cols
            values << offsetsModel.getValueAt(row, col).toString()
        }
        writer.write(values.join(",") + "\n")
    }
    writer.close()

}



def openPair(frontFile, sideFile) {
    // --- stop any playing video ---
    if (playTimer) {
        playTimer.cancel()
        playing = false
    }

    // Close all previous windows
    while (WindowManager.getImageCount() > 0) {
        WindowManager.getCurrentImage().close()
    }

    // ✅ compute CoreID from filename
    def coreID = getBaseName(frontFile.name)

    // Load exclude_table.csv if present
    def excluded = [] as Set
    def exFile = new File(new File(dir, "OUT"), "exclude_table.csv")
    if (exFile.exists()) {
        exFile.eachLine { line, i ->
            if (i == 0 || !line) return
            def parts = line.split(",")
            if (parts.size() >= 2 && parts[1].trim() == "1") {
                excluded.add(parts[0].trim())
            }
        }
    }

    // ✅ Skip excluded videos
    if (excluded.contains(coreID)) {
        lblInfo.setText("CoreID: " + coreID + " | ❌ Excluded")
        IJ.showStatus("Skipping excluded video: " + coreID)
          // 🔔 Show popup once per skip
        IJ.showMessage("Excluded Video",
            "The video for CoreID '" + coreID + "' is marked as excluded.\n" +
            "Use MATLAB to uncheck it if you want to include it again.")

        return
    }

    // --- Open both videos ---
    IJ.run("Movie (FFMPEG)...", "choose=" + sideFile.absolutePath + " use_virtual_stack first_frame=0 last_frame=-1")
    def openedSide = WindowManager.getCurrentImage()

    IJ.run("Movie (FFMPEG)...", "choose=" + frontFile.absolutePath + " use_virtual_stack first_frame=0 last_frame=-1")
    def openedFront = WindowManager.getCurrentImage()

    impFront = openedFront
    impSide  = openedSide
    IJ.run("Tile")

    // ✅ reset to first frame
    if (impSide)  impSide.setSlice(1)
    if (impFront) impFront.setSlice(1)

    // --- load saved Offset1 if available ---
    def off = 0
    def found = false
    idx = findRowIndex(coreID)
    if (idx >= 0) {
        try {
            off = offsetsModel.getValueAt(idx, 3).toString().toInteger()  // column 3 = Offset1
            found = true
        } catch (Exception e) {
            off = 0
        }
    }

    // ✅ update text field and globals
    txtOffset.setText(off.toString())
    savedOffset = off

    // ✅ update label with CoreID and position
    lblInfo.setText("CoreID: " + coreID + " | Video " + (fileIndex+1) + " / " + frontFiles.size())

    idx = findRowIndex(coreID)
    if (idx >= 0) {
        tblOffsets.setRowSelectionInterval(idx, idx)
        tblOffsets.scrollRectToVisible(tblOffsets.getCellRect(idx, 0, true))
    }


    if (found) {
        IJ.showStatus("Loaded Offset1 = " + off + " for " + coreID)
    } else {
        IJ.showStatus("No saved Offset1 found for " + coreID)
    }
}



def getBaseName(fileName) {
    def base = fileName
    if (base.toLowerCase().endsWith(".mp4")) {
        base = base.substring(0, base.length() - 4)
    }
    base = base.replace("_Front_", "_").replace("_Side_", "_")
    base = base.replace("_Front", "").replace("_Side", "")
    return base
}

def findRowIndex(coreID) {
    for (int i=0; i<offsetsModel.getRowCount(); i++) {
        if (offsetsModel.getValueAt(i,0).toString() == coreID) return i
    }
    return -1
}

// helper for VideoSyncTool
def findVideoByCoreAndTag(File folder, String coreID, String tag) {
    if (!folder.exists()) return null
    def expectedName = coreID.replaceFirst("_", "_${tag}_") + ".mp4"
    def f = new File(folder, expectedName)
    return f.exists() ? f : null
}

btnOpen.addActionListener({
    loadOffsetsTable()

    def frontFolder = new File(dir, "Front")
    def sideFolder  = new File(dir, "Side")

    int viewRow = tblOffsets.getSelectedRow()
    if (viewRow >= 0) {
        int modelRow = tblOffsets.convertRowIndexToModel(viewRow)
        def rawID  = offsetsModel.getValueAt(modelRow, 0).toString()
        def coreID = getBaseName(rawID)

        // 🔍 find the matching file in Front folder
        frontFiles = frontFolder.listFiles()?.findAll { it.name.endsWith(".mp4") && it.name.contains("Front") }?.sort { it.name }
        fileIndex = frontFiles.findIndexOf { getBaseName(it.name) == coreID }

        if (fileIndex < 0) {
            IJ.error("Could not find Front video for " + coreID)
            return
        }

        currentFrontFile = frontFiles[fileIndex]
        currentSideFile  = findVideoByCoreAndTag(sideFolder, coreID, "Side")
        if (!currentFrontFile || !currentSideFile) {
            IJ.error("Missing Front/Side for " + coreID)
            return
        }

        // ✅ update GUI consistency
        txtOpenIndex.setText((fileIndex + 1).toString())
        tblOffsets.setRowSelectionInterval(modelRow, modelRow)
        tblOffsets.scrollRectToVisible(tblOffsets.getCellRect(modelRow, 0, true))

        openPair(currentFrontFile, currentSideFile)
    } else {
        IJ.error("Please select a row in the table first.")
    }
})


btnNext.addActionListener({
    if (!frontFiles) { IJ.error("Hit Open first"); return }
    fileIndex++
    if (fileIndex >= frontFiles.size()) {
        fileIndex = frontFiles.size() - 1
        IJ.showMessage("No more videos")
        return
    }

    def coreID = getBaseName(frontFiles[fileIndex].name)

    int rowIdx = findRowIndex(coreID)
    if (rowIdx >= 0) {
        tblOffsets.setRowSelectionInterval(rowIdx, rowIdx)
        tblOffsets.scrollRectToVisible(tblOffsets.getCellRect(rowIdx, 0, true))
        txtOpenIndex.setText((fileIndex + 1).toString())
    }

    def sideFile = new File(new File(dir,"Side"), frontFiles[fileIndex].name.replace("Front","Side"))
    if (!sideFile.exists()) {
        IJ.error("Missing Side: " + sideFile.name)
        return
    }

    currentFrontFile = frontFiles[fileIndex]
    currentSideFile  = sideFile
    openPair(currentFrontFile, currentSideFile)
})

btnPrev.addActionListener({
    if (!frontFiles) { IJ.error("Hit Open first"); return }
    fileIndex--
    if (fileIndex < 0) {
        fileIndex = 0
        IJ.showMessage("At first video")
        return
    }

    def coreID = getBaseName(frontFiles[fileIndex].name)

    int rowIdx = findRowIndex(coreID)
    if (rowIdx >= 0) {
        tblOffsets.setRowSelectionInterval(rowIdx, rowIdx)
        tblOffsets.scrollRectToVisible(tblOffsets.getCellRect(rowIdx, 0, true))
        txtOpenIndex.setText((fileIndex + 1).toString())
    }

    def sideFile = new File(new File(dir,"Side"), currentFrontFile.name.replace("Front","Side"))
    if (!sideFile.exists()) {
        IJ.error("Missing Side: " + sideFile.name)
        return
    }

    currentFrontFile = frontFiles[fileIndex]
    currentSideFile  = sideFile
    openPair(currentFrontFile, currentSideFile)
})




btnPlay.addActionListener({
    if (!impFront || !impSide) {
        IJ.error("No videos open")
        return
    }
    if (playing) {
        return
    }

    def fps = txtFps.text.toInteger()
    def offset = txtOffset.text.toInteger()
    def delay = (int)(1000.0 / fps)

    def nFrames = Math.min(impSide.getStackSize(), impFront.getStackSize() - Math.abs(offset))
    def slices = [impSide.getCurrentSlice()]

    playTimer = new Timer()
    playing = true

    playTimer.scheduleAtFixedRate(new TimerTask() {
        void run() {
            if (slices[0] > nFrames) {
                playTimer.cancel()
                playing = false
                return
            }
            def sideIndex  = slices[0]
            def frontIndex = sideIndex + offset
            impSide.setSlice(sideIndex)
            if (frontIndex >= 1 && frontIndex <= impFront.getStackSize()) {
                impFront.setSlice(frontIndex)
            }
            slices[0]++
        }
    }, 0, delay)
})

btnPause.addActionListener({
    if (playTimer) {
        playTimer.cancel()
        playing = false
        IJ.showStatus("Playback paused")
    }
})

btnTestOffset.addActionListener({
    if (!impFront || !impSide) {
        IJ.error("No videos open")
        return
    }
    def off = impFront.getCurrentSlice() - impSide.getCurrentSlice()
    txtOffset.setText(off.toString())
    savedOffset = off
})

btnSaveOffset1.addActionListener({
    if (!impFront || !impSide) { IJ.error("No videos open"); return }

    def off = txtOffset.text.toInteger()
    def SideFrame = impSide.getCurrentSlice()
    def FrontFrame = impFront.getCurrentSlice()

    // ✅ CoreID from selected row instead of currentFrontFile
    int viewRow = tblOffsets.getSelectedRow()
    if (viewRow < 0) { IJ.error("Select a row in the table first"); return }
    int modelRow = tblOffsets.convertRowIndexToModel(viewRow)
    def coreID = offsetsModel.getValueAt(modelRow, 0).toString()

    if (modelRow >= 0) {
        offsetsModel.setValueAt(SideFrame, modelRow, 1)
        offsetsModel.setValueAt(FrontFrame, modelRow, 2)
        offsetsModel.setValueAt(off, modelRow, 3)
    } else {
        def isExcluded = excluded.contains(coreID)
        offsetsModel.addRow([coreID, SideFrame, FrontFrame, off, 0, 0, 0, isExcluded] as Object[])
    }

    saveOffsetsTableToCSV()
    IJ.showStatus("Saved Offset 1 = " + off + " for " + coreID)
})

btnSaveOffset2.addActionListener({
    if (!impFront || !impSide) { IJ.error("No videos open"); return }

    def off = txtOffset.text.toInteger()
    def SideFrame = impSide.getCurrentSlice()
    def FrontFrame = impFront.getCurrentSlice()

    // ✅ CoreID from selected row
    int viewRow = tblOffsets.getSelectedRow()
    if (viewRow < 0) { IJ.error("Select a row in the table first"); return }
    int modelRow = tblOffsets.convertRowIndexToModel(viewRow)
    def coreID = offsetsModel.getValueAt(modelRow, 0).toString()

    if (modelRow >= 0) {
        offsetsModel.setValueAt(SideFrame, modelRow, 4)
        offsetsModel.setValueAt(FrontFrame, modelRow, 5)
        offsetsModel.setValueAt(off, modelRow, 6)
    } else {
        def isExcluded = excluded.contains(coreID)
        offsetsModel.addRow([coreID, 0, 0, 0, SideFrame, FrontFrame, off, isExcluded] as Object[])
    }

    saveOffsetsTableToCSV()
    IJ.showStatus("Saved Offset 2 = " + off + " for " + coreID)
})


btnApplyOffset.addActionListener({
    if (!impFront || !impSide) {
        IJ.error("No videos open")
        return
    }
    def off = txtOffset.text.toInteger()
    savedOffset = off
    def sideIndex = impSide.getCurrentSlice()
    def frontIndex = sideIndex + off
    if (frontIndex < 1 || frontIndex > impFront.getStackSize()) {
        IJ.error("Offset out of range")
        return
    }
    impFront.setSlice(frontIndex)
    IJ.showStatus("Applied offset " + off + " (Front=" + frontIndex + ", Side=" + sideIndex + ")")
})

btnBackMatlab.addActionListener({
    // Save before leaving
    saveOffsetsTableToCSV()

    // (Optional) Show message
    IJ.showMessage("Offsets saved. You can continue in MATLAB.")

    // Exit FIJI (ImageJ)
    IJ.run("Quit")
})
