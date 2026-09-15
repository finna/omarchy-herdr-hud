import QtQuick

// Flat WoW badge: one gold silhouette, blue center, and no side studs.
Item {
  id: root
  property bool hovered: false

  Canvas {
    anchors.fill: parent
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2, cy = height / 2, size = Math.min(width, height)
      var radius = size * 0.36
      // Build a single outline so the small tips have no seams or extra rings.
      ctx.beginPath()
      for (var step = 0; step <= 128; step++) {
        var angle = step * Math.PI * 2 / 128
        var tip = 0
        for (var i = 1; i < 8; i++) {
          if (i === 4) continue // No left/right protrusions.
          var delta = Math.abs(angle - i * Math.PI / 4)
          delta = Math.min(delta, Math.PI * 2 - delta)
          tip = Math.max(tip, Math.max(0, 1 - delta / 0.16))
        }
        var r = radius + size * 0.075 * tip
        var x = cx + Math.cos(angle) * r
        var y = cy + Math.sin(angle) * r
        if (step === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.closePath()
      ctx.fillStyle = "#d5bb83"
      ctx.fill()
      ctx.beginPath()
      ctx.arc(cx, cy, radius - size * 0.045, 0, Math.PI * 2)
      ctx.fillStyle = "#176482"
      ctx.fill()
    }
  }

  Text {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: 1
    text: "H"
    color: root.hovered ? "#f3dda8" : "#d5bb83"
    font.family: "Georgia"
    font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.48)
    font.bold: true
  }
}
