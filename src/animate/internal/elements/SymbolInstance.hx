package animate.internal.elements;

import animate.FlxAnimateJson;
import animate.internal.elements.Element;
import animate.internal.filters.Blend;
import flixel.FlxCamera;
import flixel.math.FlxMath;
import flixel.math.FlxMatrix;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.system.FlxAssets.FlxShader;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import openfl.display.BlendMode;
import openfl.geom.ColorTransform;

using flixel.util.FlxColorTransformUtil;

class SymbolInstance extends AnimateElement<SymbolInstanceJson>
{
	public var libraryItem:SymbolItem;
	public var blend:BlendMode;
	public var firstFrame:Int;
	public var loopType:LoopType;
	public var symbolName(get, never):String;
	public var transformationPoint:FlxPoint;

	var isColored:Bool;
	var transform:ColorTransform;
	var _transform:ColorTransform;

	public function new(?data:SymbolInstanceJson, ?parent:FlxAnimateFrames, ?frame:Frame)
	{
		super(data, parent, frame);
		this.elementType = GRAPHIC;

		if (data == null)
			return;

		this.libraryItem = parent.getSymbol(data.SN);
		this.matrix = data.MX.toMatrix();
		this.firstFrame = data.FF ?? 0;
		this.isColored = false;

		this.loopType = switch (data.LP)
		{
			case "PO" | "playonce": LoopType.PLAY_ONCE;
			case "SF" | "singleframe": LoopType.SINGLE_FRAME;
			default: LoopType.LOOP;
		}

		var trp:Null<TransformationPointJson> = data.TRP;
		this.transformationPoint = FlxPoint.get(trp?.x ?? 0.0, trp?.y ?? 0.0);

		if (libraryItem == null)
			visible = false;

		var color = data.C;
		if (color != null)
		{
			switch (color.M)
			{
				case "AD" | "Advanced":
					setColorTransform(color.RM ?? 1.0, color.GM ?? 1.0, color.BM ?? 1.0, color.AM ?? 1.0, color.RO ?? 0.0, color.GO ?? 0.0, color.BO ?? 0.0, color.AO ?? 0.0);
				case "CA" | "Alpha":
					setColorTransform(1.0, 1.0, 1.0, color.AM ?? 1.0, 0.0, 0.0, 0.0, 0.0);
				case "CBRT" | "Brightness":
					var brightness = color.BRT ?? 0.0;
					var colorMult = 1.0 - Math.abs(brightness);
					var colorOff = brightness >= 0.0 ? brightness * 255.0 : 0.0;
					setColorTransform(colorMult, colorMult, colorMult, 1.0, colorOff, colorOff, colorOff, 0.0);
				case "T" | "Tint":
					var tintStr:String = color.TC ?? "#FFFFFF";
					var tint:FlxColor = FlxColor.fromString(tintStr);
					var tintMult:Float = color.TM ?? 0.0;
					var mult:Float = 1.0 - tintMult;
					setColorTransform(mult, mult, mult, 1.0, tint.red * tintMult, tint.green * tintMult, tint.blue * tintMult, 0.0);
			}
		}
	}

	public extern overload inline function setColorTransform(rMult:Float = 1, gMult:Float = 1, bMult:Float = 1, aMult:Float = 1, rOffset:Float = 0,
			gOffset:Float = 0, bOffset:Float = 0, aOffset:Float = 0):Void
	{
		_setColorTransform(rMult, gMult, bMult, aMult, rOffset, gOffset, bOffset, aOffset);
	}

	public extern overload inline function setColorTransform(color:FlxColor):Void
	{
		_setColorTransform(color.redFloat, color.greenFloat, color.blueFloat, 1, 0, 0, 0, 0);
	}

	/**
	 * Returns the timeline frame index needed to be rendered at a specific frame, while taking loop types into consideration.
	 * @param index 		Index of the timeline to render.
	 * @param frameIndex 	Optional, relative frame index of the current keyframe the symbol instance is stored at.
	 * @return				Found frame index for rendering at a specific frame.
	 */
	public function getFrameIndex(index:Int, frameIndex:Int = 0):Int
	{
		var frameTarget = firstFrame + (index - frameIndex);
		
		if (libraryItem == null || libraryItem.timeline == null) 
			return firstFrame;

		var frameCount = libraryItem.timeline.frameCount;

		switch (loopType)
		{
			case LoopType.LOOP:
				frameTarget = FlxMath.wrap(frameTarget, 0, frameCount > 0 ? frameCount - 1 : 0);
			case LoopType.PLAY_ONCE:
				frameTarget = FlxMath.minInt(frameTarget, frameCount > 0 ? frameCount - 1 : 0);
			case LoopType.SINGLE_FRAME:
				frameTarget = firstFrame;
		}

		return frameTarget;
	}

	/**
	 * Method used internally to check if a symbol has simple rendering (one frame).
	 * @return If the symbol has simple rendering or not.
	 */
	public function isSimpleSymbol():Bool
	{
		if (libraryItem == null || libraryItem.timeline == null)
			return true;

		var timeline = libraryItem.timeline;

		if (timeline.frameCount <= 1)
			return true;

		if (loopType == SINGLE_FRAME)
			return true;

		return false;
	}

	var _tmpMatrix:FlxMatrix = new FlxMatrix();

	override function getBounds(frameIndex:Int, ?rect:FlxRect, ?matrix:FlxMatrix, ?includeFilters:Bool = true, ?useCachedBounds:Bool = false):FlxRect
	{
		// safeguard
		if (libraryItem != null && libraryItem.timeline != null && libraryItem.timeline.parent != null && libraryItem.timeline.parent.existsSymbol(symbolName))
			libraryItem = libraryItem.timeline.parent.getSymbol(symbolName);

		// Prepare the bounds matrix
		var targetMatrix:FlxMatrix;
		if (matrix != null)
		{
			_tmpMatrix.copyFrom(this.matrix);
			_tmpMatrix.concat(matrix);
			targetMatrix = _tmpMatrix;
		}
		else
		{
			targetMatrix = this.matrix;
		}

		if (libraryItem == null || libraryItem.timeline == null)
			return FlxRect.get(0, 0, 0, 0);

		// Get the bounds of the symbol item timeline
		return libraryItem.timeline.getBounds(getFrameIndex(frameIndex, 0), null, rect, targetMatrix, includeFilters, useCachedBounds);
	}

	override function draw(camera:FlxCamera, index:Int, frameIndex:Int, parentMatrix:FlxMatrix, ?transform:ColorTransform, ?blend:BlendMode,
			?antialiasing:Bool, ?shader:FlxShader):Void
	{
		if (isColored) // Concat symbol's color to the current color transform
		{
			var t = this.transform;

			_transform.redMultiplier = t.redMultiplier;
			_transform.greenMultiplier = t.greenMultiplier;
			_transform.blueMultiplier = t.blueMultiplier;
			_transform.alphaMultiplier = t.alphaMultiplier;

			_transform.redOffset = t.redOffset;
			_transform.greenOffset = t.greenOffset;
			_transform.blueOffset = t.blueOffset;
			_transform.alphaOffset = t.alphaOffset;

			if (transform != null)
				_transform.concat(transform);

			transform = _transform;

			if (transform.alphaMultiplier <= 0)
				return;
		}

		var b = Blend.resolve(this.blend, blend);
		_drawTimeline(camera, index, frameIndex, parentMatrix, transform, b, antialiasing, shader);
	}

	function _drawTimeline(camera:FlxCamera, index:Int, frameIndex:Int, parentMatrix:FlxMatrix, transform:Null<ColorTransform>, blend:Null<BlendMode>,
			antialiasing:Null<Bool>, shader:Null<FlxShader>)
	{
		if (libraryItem == null || libraryItem.timeline == null)
			return;

		_mat.copyFrom(matrix);
		_mat.concat(parentMatrix);
		libraryItem.timeline.currentFrame = getFrameIndex(index, frameIndex);
		libraryItem.timeline.draw(camera, _mat, transform, blend, antialiasing, shader);
	}

	function _setColorTransform(rMult:Float, gMult:Float, bMult:Float, aMult:Float, rOffset:Float, gOffset:Float, bOffset:Float, aOffset:Float)
	{
		if (transform == null)
			transform = new ColorTransform();
		if (_transform == null)
			_transform = new ColorTransform();

		transform.redMultiplier = rMult;
		transform.greenMultiplier = gMult;
		transform.blueMultiplier = bMult;
		transform.alphaMultiplier = aMult;

		transform.redOffset = rOffset;
		transform.greenOffset = gOffset;
		transform.blueOffset = bOffset;
		transform.alphaOffset = aOffset;

		isColored = (transform.hasRGBAMultipliers() || transform.hasRGBAOffsets());
	}

	inline function get_symbolName():String
	{
		return libraryItem?.name;
	}

	override function destroy()
	{
		super.destroy();
		transformationPoint = FlxDestroyUtil.put(transformationPoint);
		libraryItem = null;
		transform = null;
		_transform = null;
		_tmpMatrix = null;
	}

	public function toString():String
	{
		return '{name: ${libraryItem?.name}, matrix: $matrix}';
	}
}

enum abstract LoopType(Int) to Int
{
	var LOOP;
	var PLAY_ONCE;
	var SINGLE_FRAME;

	public function toString():String
	{
		return switch (cast this : LoopType)
		{
			case LOOP: "loop";
			case PLAY_ONCE: "play_once";
			case SINGLE_FRAME: "single_frame";
		}
	}
}
