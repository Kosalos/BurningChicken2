import UIKit
import Metal
import simd

var control = Control()
var vc:ViewController! = nil

var isDirty:Bool = false
let GESTURE_ENDED:Float = 9999

class ViewController: UIViewController, WGDelegate {
    var controlBuffer:MTLBuffer! = nil
    var colorBuffer:MTLBuffer! = nil
    var texture1: MTLTexture!
    var texture2: MTLTexture!
    var pipeline:[MTLComputePipelineState] = []
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    var shadowFlag:Bool = false
    var d2View:MetalTextureView! = nil
    var wg:WidgetGroup! = nil

    var threadGroupCount = MTLSize() // MTLSizeMake(22,22,1) // 20,20, 1)
    var threadGroups = MTLSize()
    
    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        
        d2View = MetalTextureView()
        wg = WidgetGroup()
        view.addSubview(d2View)
        view.addSubview(wg)

        initializeWidgetGroup()
        
        func loadShader(_ name:String) -> MTLComputePipelineState {
            do {
                let defaultLibrary:MTLLibrary! = self.device.makeDefaultLibrary()
                guard let fn = defaultLibrary.makeFunction(name: name)  else { print("shader not found: " + name); exit(0) }
                return try device.makeComputePipelineState(function: fn)
            }
            catch { print("pipeline failure for : " + name); exit(0) }
        }
        
        let shaderNames = [ "fractalShader","shadowShader" ]
        for i in 0 ..< shaderNames.count { pipeline.append(loadShader(shaderNames[i])) }
        
        controlBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        
        let jbSize = MemoryLayout<float3>.stride * 256
        colorBuffer = device.makeBuffer(length:jbSize, options:MTLResourceOptions.storageModeShared)
        colorBuffer.contents().copyMemory(from:colorMap, byteCount:jbSize)
        
        let WgWidth:CGFloat = 120
        wg.frame = CGRect(x:0, y:0, width:WgWidth, height:view.bounds.height)
        d2View.frame = CGRect(x:WgWidth, y:0, width:view.bounds.width-WgWidth, height:view.bounds.height)
        
        setImageViewResolutionAndThreadGroups()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        d2View.initialize(texture1)
        
        Timer.scheduledTimer(withTimeInterval:0.01, repeats:true) { timer in self.timerHandler() }
        control.coloringFlag = 1
        control.chickenFlag = 0
        wgCommand(.reset)
    }
    
    //MARK: -
    
    var zoomValue:Float = GESTURE_ENDED
    var panValueX:Float = GESTURE_ENDED
    var panValueY:Float = GESTURE_ENDED

    @objc func timerHandler() {
        var refreshNeeded:Bool = false
        
        if wg.update() { refreshNeeded = true }
        
        if zoomValue != GESTURE_ENDED { performZoom(); refreshNeeded = true }
        if panValueX != GESTURE_ENDED { performAlterPosition(); refreshNeeded = true }
        
        if refreshNeeded { updateImage() }
    }
    
    //MARK: -
    
    func updateImage() {
        isDirty = true  // so metalView only draws when necessary
        calcFractal()
        d2View.display(d2View.layer)
    }
    
    //MARK: -
    
    func initializeWidgetGroup() {
        wg.delegate = self
        wg.initialize()
        
        wg.addCommand("Reset",.reset)
        wg.addCommand("Save/Load",.saveLoad)
        wg.addCommand("Load Next",.loadNext)
        wg.addCommand("Help",.help)
        wg.addLine()
        wg.addSingleFloat(&control.maxIter,40,200,30,"maxIter")
        wg.addSingleFloat(&control.contrast,0.1,5,0.3, "Contrast")
        wg.addSingleFloat(&control.skip,1,100,2,"Skip")
        wg.addLine()
        wg.addColor(1,Float(RowHT)+3);  wg.addCommand("Chicken",.chicken)
        wg.addLine()
        wg.addColor(2,Float(RowHT)+3);  wg.addCommand("Shadow",.shadow)
        
        wg.addLine()
        wg.addColor(3,Float(RowHT)*7+3);
        wg.addCommand("Coloring",.coloring)
        wg.addSingleFloat(&control.stripeDensity,-10,10,0.3, "Stripe")
        wg.addSingleFloat(&control.escapeRadius,0.01,4,0.1, "Escape")
        wg.addSingleFloat(&control.multiplier,-2,2,0.1, "Mult")
        wg.addSingleFloat(&control.R,0,1,0.08, "Color R")
        wg.addSingleFloat(&control.G,0,1,0.08, "Color G")
        wg.addSingleFloat(&control.B,0,1,0.08, "Color B")
        wg.addLine()
        wg.addLegend(" ")
        wg.addLegend("2 Fingers")
        wg.addLegend("to Pan")
        wg.addLegend(" ")
        wg.addLegend("Pinch")
        wg.addLegend("to Zoom")
    }
    
    //MARK: -
    
    func setImageViewResolutionAndThreadGroups() {
        control.xSize = Int32(d2View.bounds.size.width)
        control.ySize = Int32(d2View.bounds.size.height)
        
        let xsz = Int(control.xSize)
        let ysz = Int(control.ySize)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: xsz,
            height: ysz,
            mipmapped: false)
        texture1 = self.device.makeTexture(descriptor: textureDescriptor)!
        texture2 = self.device.makeTexture(descriptor: textureDescriptor)!
        
        let w = pipeline[0].threadExecutionWidth
        let h = pipeline[0].maxTotalThreadsPerThreadgroup / w
        threadGroupCount = MTLSizeMake(w, h, 1)
        
        let maxsz = max(xsz,ysz) + Int(threadGroupCount.width-1)
        threadGroups = MTLSizeMake( maxsz / threadGroupCount.width, maxsz / threadGroupCount.height,1)
    }
    
    //MARK: -
    
    func performAlterPosition() {
        if panValueX == GESTURE_ENDED { return }
        let mx = (control.xmax - control.xmin) * panValueX / 500
        let my = (control.ymax - control.ymin) * panValueY / 500
        control.xmin -= mx
        control.xmax -= mx
        control.ymin -= my
        control.ymax -= my
        
        updateImage()
    }
    
    func wgAlterPosition(_ dx:Float, _ dy:Float) { panValueX = dx; panValueY = dy }
    
    //MARK: -
    
    func performZoom() {
        if zoomValue == GESTURE_ENDED { return }
        let deltaZoom:Float = (1 - (zoomValue - 1.0) * 0.1)
        // Swift.print("zoom : ",dz.description,"  dz:  ",deltaZoom)

        let xsize = (control.xmax - control.xmin) * deltaZoom
        let ysize = (control.ymax - control.ymin) * deltaZoom
        let xc = (control.xmin + control.xmax) / 2
        let yc = (control.ymin + control.ymax) / 2
        
        control.xmin = xc - xsize/2
        control.xmax = xc + xsize/2
        control.ymin = yc - ysize/2
        control.ymax = yc + ysize/2
    }
    
    func wgAlterZoom(_ dz:Float) { zoomValue = dz }
    
    //MARK: -
    
    func wgRefresh() { updateImage() }
    
    func wgCommand(_ cmd:CmdIdent) {
        switch(cmd) {
        case .saveLoad : performSegue(withIdentifier: "saveLoadSegue", sender: self)
        case .help : performSegue(withIdentifier: "helpSegue", sender: self)
            
        case .reset :
            control.xmin = -2
            control.xmax = 1
            control.ymin = -1.5
            control.ymax = 1.5
            control.skip = 20
            control.stripeDensity = -1.343
            control.escapeRadius = 1.702
            control.multiplier = -0.381
            control.R = 0
            control.G = 0.4
            control.B = 0.7
            control.maxIter = 50
            control.contrast = 1
            
            updateImage()

        case .coloring :
            control.coloringFlag = control.coloringFlag == 0 ? 1 : 0
            updateImage()
            
        case .chicken :
            control.chickenFlag = control.chickenFlag == 0 ? 1 : 0
            wgCommand(.reset)
            
        case .shadow :
            shadowFlag = !shadowFlag
            d2View.initialize(shadowFlag ? texture2 : texture1)
            updateImage()
            
        case .loadNext :
            let ss = SaveLoadViewController()
            ss.loadNext()
            updateImage()
        }
    }
    
    func wgGetString(_ index:Int) -> String { return "unused" }
    
    func wgGetColor(_ index:Int) -> UIColor {
        let c1 = UIColor(red:0.2, green:0.2, blue:0.2, alpha:1)
        let c2 = UIColor(red:0.3, green:0.2, blue:0.2, alpha:1)
        
        switch(index) {
        case 1  : return control.chickenFlag > 0 ? c2 : c1
        case 2  : return shadowFlag ? c2 : c1
        case 3  : return control.coloringFlag > 0 ? c2 : c1
        default : return .white
        }
    }
    
    //MARK: -
    
    func calcFractal() {
        control.dx = (control.xmax - control.xmin) / Float(control.xSize)
        control.dy = (control.ymax - control.ymin) / Float(control.ySize)
        controlBuffer.contents().copyMemory(from: &control, byteCount:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline[0])
        commandEncoder.setTexture(texture1, index: 0)
        commandEncoder.setBuffer(controlBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(colorBuffer, offset: 0, index: 1)
        
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if shadowFlag {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!

            commandEncoder.setComputePipelineState(pipeline[1])
            commandEncoder.setTexture(texture1, index: 0)
            commandEncoder.setTexture(texture2, index: 1)
            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            commandEncoder.endEncoding()

            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }
    
    override var prefersStatusBarHidden: Bool { return true }
}

// MARK:

func drawLine(_ context:CGContext, _ p1:CGPoint, _ p2:CGPoint) {
    context.beginPath()
    context.move(to:p1)
    context.addLine(to:p2)
    context.strokePath()
}

func drawVLine(_ context:CGContext, _ x:CGFloat, _ y1:CGFloat, _ y2:CGFloat) { drawLine(context,CGPoint(x:x,y:y1),CGPoint(x:x,y:y2)) }
func drawHLine(_ context:CGContext, _ x1:CGFloat, _ x2:CGFloat, _ y:CGFloat) { drawLine(context,CGPoint(x:x1, y:y),CGPoint(x: x2, y:y)) }

func drawRect(_ context:CGContext, _ r:CGRect) {
    context.beginPath()
    context.addRect(r)
    context.strokePath()
}

func drawFilledCircle(_ context:CGContext, _ center:CGPoint, _ diameter:CGFloat, _ color:CGColor) {
    context.beginPath()
    context.addEllipse(in: CGRect(x:CGFloat(center.x - diameter/2), y:CGFloat(center.y - diameter/2), width:CGFloat(diameter), height:CGFloat(diameter)))
    context.setFillColor(color)
    context.fillPath()
}

//MARK:-

var fntSize:CGFloat = 0
var txtColor:UIColor = .clear
var textFontAttributes:NSDictionary! = nil

func drawText(_ x:CGFloat, _ y:CGFloat, _ color:UIColor, _ sz:CGFloat, _ str:String) {
    if sz != fntSize || color != txtColor {
        fntSize = sz
        txtColor = color
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = NSTextAlignment.left
        let font = UIFont.init(name: "Helvetica", size:sz)!
        
        textFontAttributes = [
            NSAttributedStringKey.font: font,
            NSAttributedStringKey.foregroundColor: color,
            NSAttributedStringKey.paragraphStyle: paraStyle,
        ]
    }
    
    str.draw(in: CGRect(x:x, y:y, width:800, height:100), withAttributes: textFontAttributes as? [NSAttributedStringKey : Any])
}

