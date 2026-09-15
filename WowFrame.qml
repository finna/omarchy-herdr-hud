import QtQuick

// Small cut corners and layered bronze edges, without bitmap dependencies.
Canvas {
  id: frame
  property color fillColor: "transparent"
  antialiasing: true
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onVisibleChanged: if (visible) requestPaint()
  onFillColorChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    function outline(inset, cut) {
      var l = inset, t = inset, r = width - inset, b = height - inset
      ctx.beginPath()
      ctx.moveTo(l + cut, t)
      ctx.lineTo(r - cut, t)
      ctx.lineTo(r, t + cut)
      ctx.lineTo(r, b - cut)
      ctx.lineTo(r - cut, b)
      ctx.lineTo(l + cut, b)
      ctx.lineTo(l, b - cut)
      ctx.lineTo(l, t + cut)
      ctx.closePath()
    }
    outline(1.5, 7)
    if (fillColor.a > 0) {
      ctx.fillStyle = fillColor
      ctx.fill()
    }
    ctx.lineWidth = 3
    ctx.strokeStyle = "#32271b"
    ctx.stroke()
    var bronze = ctx.createLinearGradient(0, 0, width * 0.3, height)
    bronze.addColorStop(0, "#c3a574")
    bronze.addColorStop(0.16, "#78603e")
    bronze.addColorStop(0.52, "#40321f")
    bronze.addColorStop(0.85, "#927348")
    bronze.addColorStop(1, "#b29460")
    outline(3, 6)
    ctx.lineWidth = 2
    ctx.strokeStyle = bronze
    ctx.stroke()
    outline(5, 5)
    ctx.lineWidth = 1
    ctx.strokeStyle = "#0b0906"
    ctx.stroke()
  }
}
