package animate;

import animate.FlxAnimateJson;
import animate.internal.SymbolItem;
import animate.internal.Timeline;
import animate.internal.elements.SymbolInstance;
import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFramesCollection.FlxFrameCollectionType;
import flixel.math.FlxMatrix;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.system.FlxAssets.FlxGraphicAsset;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import haxe.Json;
import haxe.ds.Vector;
import haxe.io.Path;

using StringTools;

/**
 * Settings used when first loading a texture atlas.
 *
 * @param swfMode 			Used if the movieclips of the symbol should render similarly to SWF files. Disabled by default.
 * See ``animate.internal.elements.MovieClipInstance`` for more.
 *
 * @param cacheOnLoad		If to cache all necessary filters and masks when the texture atlas is first loaded. Disabled by default.
 *							This setting may be useful for reducing lag on filter heavy atlases. But take into account that
 *							it can also heavily increase loading times.
 *
 * @param filterQuality		Level of compression used to render filters. Set to ``MEDIUM`` by default.
 *							``HIGH`` 	-> Will render filters at their full quality, with no resolution loss.
 *							``MEDIUM`` 	-> Will apply some lossless compression to the filter, most recommended option.
 *							``LOW`` 	-> Will use heavy and easily noticeable compression, use with precausion.
 *							``RUDY``	-> Having your eyes closed probably has better graphics than this.
 *
 * @param onSymbolCreate	An optional callback that gets called when a ``SymbolItem`` is created and added to the library.
 * This setting can be used as a intermeddiate point in the Texture Atlas loading process to add
 * any custom changes that may want to be applied before any baking is applied to the Texture Atlas.
 */
typedef FlxAnimateSettings =
{
	?swfMode:Bool,
	?cacheOnLoad:Bool,
	?filterQuality:FilterQuality,
	?onSymbolCreate:SymbolItem->Void
}

/**
 * Class used to store all the data needed for texture atlases, such as spritemaps, symbols...
 *
 * Note that this engine does **NOT** convert texture atlases into spritesheets, therefore trying to get
 * frames from a ``FlxAnimateFrames`` will result in getting the limb frames of the spritemap.
 *
 * If you need an actual frame of the texture atlas animation I recommend manually creating it using
 * ``framePixels`` on a ``FlxAnimate``. Though it may cause performance issues, so use with precaution.
 */
class FlxAnimateFrames extends FlxAtlasFrames
{
	public var timeline:Timeline;

	public var stageRect:FlxRect;

	public var stageColor:FlxColor;

	public var matrix:FlxMatrix; 

	public var frameRate:Float;

	public function new(graphic:FlxGraphic)
	{
		super(graphic);
		this.dictionary = [];
		this.addedCollections = [];
	}

	public function getSymbol(name:String):Null<SymbolItem>
	{
		if (dictionary.exists(name))
		{
			return dictionary.get(name);
		}
		else
		{
			if (name.contains("/"))
			{
				final shortcut:String = name.split("/").pop();
				if (dictionary.exists(shortcut))
					return dictionary.get(shortcut);
			}
		}

		if (_isInlined)
		{
			var sd = _symbolDictionary;
			if (sd != null)
			{
				for (i in 0...sd.length)
				{
					var data = sd[i];
					if (data.SN == name)
					{
						var timeline = new Timeline(data.TL, this, name);
						return setSymbol(null, new SymbolItem(timeline));
					}
				}
			}
		}
		else
		{
			if (_libraryList != null && _libraryList.contains(name))
			{
				var data:TimelineJson = Json.parse(getTextFromPath(path + "/LIBRARY/" + name + ".json"));
				var timeline = new Timeline(data, this, name);
				return setSymbol(null, new SymbolItem(timeline));
			}
		}

		for (collection in addedCollections)
		{
			if (collection.dictionary.exists(name))
				return collection.dictionary.get(name);
		}

		FlxG.log.warn("SymbolItem with name " + '"$name"' + " doesn't exist.");
		return null;
	}

	public function existsSymbol(name:String):Bool
	{
		final existsBasic:Bool = dictionary.exists(name);
		if (existsBasic)
			return true;

		if (name.contains("/"))
		{
			final shortcut:String = name.split("/").pop();
			return dictionary.exists(shortcut);
		}

		return false;
	}

	public function setSymbol(?name:String, symbolItem:SymbolItem):SymbolItem
	{
		final id:String = name ?? symbolItem.timeline.name;
		dictionary.set(id, symbolItem);
		return symbolItem;
	}

	public static function fromAnimate(animate:String, ?spritemaps:Array<SpritemapInput>, ?metadata:String, ?key:String, ?unique:Bool = false,
			?settings:FlxAnimateSettings):FlxAnimateFrames
	{
		var key:String = key ?? animate;

		if (!unique && _cachedAtlases.exists(key))
		{
			var cachedAtlas = _cachedAtlases.get(key);
			var isAtlasDestroyed = false;

			for (spritemap in cast(cachedAtlas.parent, FlxAnimateSpritemapCollection).spritemaps)
			{
				if (#if (flixel >= "5.6.0") spritemap.isDestroyed #else spritemap.bitmap == null #end)
				{
					isAtlasDestroyed = true;
					break;
				}
			}

			if (!isAtlasDestroyed)
			{
				for (frame in cachedAtlas.frames)
				{
					if (frame == null || frame.parent == null || frame.frame == null)
					{
						isAtlasDestroyed = true;
						break;
					}
				}
			}

			if (isAtlasDestroyed)
			{
				FlxG.log.warn('Texture Atlas with the key "$key" was previously cached, but incomplete. Was it incorrectly destroyed?');
				cachedAtlas.destroy();
				_cachedAtlases.remove(key);
			}
			else
			{
				return cachedAtlas;
			}
		}

		if (FlxAnimateAssets.exists(animate + "/Animation.json", TEXT))
			return _fromAnimatePath(animate, key, settings);

		return _fromAnimateInput(animate, spritemaps, metadata, key, settings);
	}

	static function getTextFromPath(path:String):String
	{
		return FlxAnimateAssets.getText(path).replace(String.fromCharCode(0xFEFF), "");
	}

	static function listWithFilter(path:String, filter:String->Bool, includeSubDirectories:Bool = false)
	{
		var list = FlxAnimateAssets.list(path, null, path.substring(0, path.indexOf(':')), includeSubDirectories);
		return list.filter(filter);
	}

	static function getGraphic(path:String):FlxGraphic
	{
		if (FlxG.bitmap.checkCache(path))
			return FlxG.bitmap.get(path);

		return FlxG.bitmap.add(FlxAnimateAssets.getBitmapData(path), false, path);
	}

	var _symbolDictionary:Null< #if flash Array<SymbolJson> #else Vector<SymbolJson> #end>;
	var _isInlined:Bool;
	var _libraryList:Array<String>;
	var _settings:Null<FlxAnimateSettings>;

	static var _cachedAtlases:Map<String, FlxAnimateFrames> = [];

	static function _fromAnimatePath(path:String, ?key:String, ?settings:FlxAnimateSettings)
	{
		var hasAnimation:Bool = FlxAnimateAssets.exists(path + "/Animation.json", TEXT);
		if (!hasAnimation)
		{
			FlxG.log.warn('No Animation.json file was found for path "$path".');
			return null;
		}

		var animation = getTextFromPath(path + "/Animation.json");
		var isInlined = !FlxAnimateAssets.exists(path + "/metadata.json", TEXT);
		var libraryList:Null<Array<String>> = null;
		var spritemaps:Array<SpritemapInput> = [];
		var metadata:Null<String> = isInlined ? null : getTextFromPath(path + "/metadata.json");

		if (!isInlined)
		{
			var list = listWithFilter(path + "/LIBRARY", (str) -> str.endsWith(".json"), true);
			libraryList = list.map((str) ->
			{
				str = str.split("/LIBRARY/").pop();
				return Path.withoutExtension(str);
			});
		}

		var spritemapList = listWithFilter(path, (file) -> Path.withoutDirectory(file).startsWith("spritemap"), false);
		var jsonList = spritemapList.filter((file) -> file.endsWith(".json"));

		for (sm in jsonList)
		{
			var cleanSm = Path.withoutDirectory(sm);
			var id = cleanSm.split("spritemap")[1].split(".")[0];
			var imageFileStr = spritemapList.filter((file) -> Path.withoutDirectory(file).startsWith('spritemap$id') && !file.endsWith(".json"))[0];

			var imgSource = imageFileStr.contains(path) ? imageFileStr : '$path/$imageFileStr';
			var jsonSource = sm.contains(path) ? sm : '$path/$sm';

			spritemaps.push({
				source: getGraphic(imgSource),
				json: getTextFromPath(jsonSource)
			});
		}

		if (spritemaps.length <= 0)
		{
			FlxG.log.warn('No spritemaps were found for key "$path". Is the texture atlas incomplete?');
			return null;
		}

		return _fromAnimateInput(animation, spritemaps, metadata, key ?? path, isInlined, libraryList, settings);
	}

	static function _fromAnimateInput(animation:String, spritemaps:Array<SpritemapInput>, ?metadata:String, ?path:String, ?isInlined:Bool = true,
			?libraryList:Array<String>, settings:FlxAnimateSettings):FlxAnimateFrames
	{
		var animData:AnimationJson = null;
		try
		{
			animData = Json.parse(animation);
		}
		catch (e)
		{
			FlxG.log.warn('Couldnt load Animation.json with input "$animation". Is the texture atlas missing?');
			return null;
		}

		if (spritemaps == null || spritemaps.length <= 0)
		{
			FlxG.log.warn('No spritemaps were added for key "$path".');
			return null;
		}

		var frames = new FlxAnimateFrames(null);
		frames.path = path;
		frames._symbolDictionary = animData.SD;
		frames._isInlined = isInlined;
		frames._libraryList = libraryList;
		frames._settings = settings;

		var spritemapCollection = new FlxAnimateSpritemapCollection(frames);
		frames.parent = spritemapCollection;

		for (spritemap in spritemaps)
		{
			var graphic = FlxG.bitmap.add(spritemap.source);
			if (graphic == null)
				continue;

			var atlas = new FlxAtlasFrames(graphic);
			var spritemap:SpritemapJson = Json.parse(spritemap.json);

			for (sprite in spritemap.ATLAS.SPRITES)
			{
				var sprite = sprite.SPRITE;
				var rect = FlxRect.get(sprite.x, sprite.y, sprite.w, sprite.h);
				var size = FlxPoint.get(sprite.w, sprite.h);
				atlas.addAtlasFrame(rect, size, FlxPoint.get(), sprite.name, sprite.rotated ? ANGLE_NEG_90 : ANGLE_0);
			}

			#if (flixel >= "5.4.0")
			frames.addAtlas(atlas);
			#else
			for (frame in atlas.frames)
				frames.pushFrame(frame);
			#end

			spritemapCollection.addSpritemap(graphic);
		}

		var metadata:MetadataJson = (metadata == null) ? animData.MD : Json.parse(metadata);

		frames.frameRate = metadata.FRT;
		frames.timeline = new Timeline(animData.AN.TL, frames, animData.AN.SN);
		frames.dictionary.set(frames.timeline.name, new SymbolItem(frames.timeline));

		var w = metadata.W;
		var h = metadata.H;
		frames.stageRect = (w > 0 && h > 0) ? FlxRect.get(0, 0, w, h) : FlxRect.get(0, 0, 1280, 720);
		
		var bgcStr:String = metadata.BGC;
		frames.stageColor = (bgcStr != null && bgcStr != "") ? FlxColor.fromString(bgcStr) : FlxColor.WHITE;

		var stageInstance:Null<SymbolInstanceJson> = animData.AN.STI;
		frames.matrix = (stageInstance != null && stageInstance.MX != null) ? stageInstance.MX.toMatrix() : new FlxMatrix();

		// Do not clear the temp data crap! Mobile/C++ targets need these properties 
		// intact for lazy symbol evaluation inside getSymbol().
		
		_cachedAtlases.set(path, frames);

		return frames;
	}

	@:allow(animate.FlxAnimateController)
	var dictionary:Map<String, SymbolItem>;

	@:allow(animate.FlxAnimateController)
	var path:String;

	@:allow(animate.FlxAnimateController)
	var addedCollections:Array<FlxAnimateFrames>;

	#if (flixel >= "5.4.0")
	override function addAtlas(collection:FlxAtlasFrames, overwriteHash:Bool = false):FlxAtlasFrames
	{
		if (collection is FlxAnimateFrames)
		{
			var animateCollection:FlxAnimateFrames = cast collection;
			addedCollections.push(animateCollection);

			var spritemap:FlxAnimateSpritemapCollection = cast animateCollection.parent;
			for (graphic in animateCollection.usedGraphics)
			{
				if (!spritemap.spritemaps.contains(graphic))
				{
					var atlasFrames = FlxAtlasFrames.findFrame(graphic);
					if (atlasFrames != null)
						super.addAtlas(atlasFrames, overwriteHash);
				}
			}

			return this;
		}

		return super.addAtlas(collection, overwriteHash);
	}

	public static extern overload inline function combineAtlas(atlasA:FlxAtlasFrames, atlasB:FlxAtlasFrames):Null<FlxAtlasFrames>
	{
		return _combineAtlas(atlasA, atlasB);
	}

	public static extern overload inline function combineAtlas(atlasList:Array<FlxAtlasFrames>):Null<FlxAtlasFrames>
	{
		if (atlasList.length <= 0)
		{
			FlxG.log.warn('No frames were found to be combined together.');
			return null;
		}

		var i = 1;
		var frames:FlxAtlasFrames = atlasList[0];
		while (i < atlasList.length)
			frames = _combineAtlas(frames, atlasList[i++]);

		return frames;
	}

	@:noCompletion
	static inline function _combineAtlas(atlasA:FlxAtlasFrames, atlasB:FlxAtlasFrames):FlxAtlasFrames
	{
		if (atlasA is FlxAnimateFrames)
			return atlasA.addAtlas(atlasB);

		return atlasB.addAtlas(atlasA);
	}
	#end

	var checkedDirtySymbols:Array<String> = [];

	function setSymbolDirty(targetSymbol:String)
	{
		if (checkedDirtySymbols.contains(targetSymbol))
			return;

		var checkForSymbol:Timeline->Void;
		checkForSymbol = (timeline:Timeline) ->
		{
			if (timeline == null || timeline.name.length <= 0)
				return;

			checkedDirtySymbols.push(timeline.name);

			for (layer in timeline)
			{
				for (frame in layer)
				{
					@:privateAccess
					if (!frame._requireBake)
						continue;

					var wasFrameSetDirty:Bool = false;
					for (element in frame)
					{
						switch (element.elementType)
						{
							case GRAPHIC | MOVIECLIP | BUTTON:
								var foundSymbol = element.toSymbolInstance().libraryItem;
								if (foundSymbol.name == targetSymbol)
								{
									if (!wasFrameSetDirty)
										frame.setDirty();
									wasFrameSetDirty = true;
								}
								else
								{
									checkForSymbol(foundSymbol.timeline);
								}
							default:
						}
					}
				}
			}
		}

		checkForSymbol(timeline);
		checkedDirtySymbols.resize(0);
	}

	override function destroy():Void
	{
		if (_cachedAtlases.exists(path))
			_cachedAtlases.remove(path);

		super.destroy();

		if (dictionary != null)
		{
			for (symbol in dictionary.iterator())
				symbol.destroy();
		}

		stageRect = FlxDestroyUtil.put(stageRect);
		timeline = FlxDestroyUtil.destroy(timeline);
		checkedDirtySymbols = null;
		dictionary = null;
		matrix = null;
	}
}

@:allow(animate.FlxAnimateFrames)
class FlxAnimateSpritemapCollection extends FlxGraphic
{
	public function new(parentFrames:FlxAnimateFrames)
	{
		super("", null);
		this.spritemaps = [];
		this.parentFrames = parentFrames;
	}

	var spritemaps:Array<FlxGraphic>;
	var parentFrames:FlxAnimateFrames;

	public function addSpritemap(graphic:FlxGraphic):Void
	{
		if (this.bitmap == null)
			this.bitmap = graphic.bitmap;

		if (spritemaps.indexOf(graphic) == -1)
			spritemaps.push(graphic);
	}

	function destroySpritemaps():Void
	{
		for (spritemap in spritemaps)
			FlxG.bitmap.remove(spritemap);

		spritemaps.resize(0);
		parentFrames = FlxDestroyUtil.destroy(parentFrames);
	}

	#if (flixel >= "5.4.0")
	override function checkUseCount():Void
	{
		if (useCount <= 0 && destroyOnNoUse && !persist)
			destroySpritemaps();
	}
	#else
	override function set_useCount(value:Int):Int
	{
		if (value <= 0 && _destroyOnNoUse && !persist)
			destroySpritemaps();
		return _useCount = value;
	}
	#end

	override function destroy():Void
	{
		bitmap = null; 
		super.destroy();
		parentFrames = null;

		if (spritemaps != null)
		{
			for (spritemap in spritemaps)
				FlxG.bitmap.remove(spritemap);
		}

		spritemaps = null;
	}
}

typedef SpritemapInput =
{
	source:FlxGraphicAsset,
	json:String
}

enum abstract FilterQuality(Int) to Int
{
	var HIGH = 0;
	var MEDIUM = 1;
	var LOW = 2;
	var RUDY = 3;

	public inline function getQualityFactor():Float
	{
		return switch (this)
		{
			case FilterQuality.MEDIUM: 1.75;
			case FilterQuality.LOW: 2.0;
			case FilterQuality.RUDY: 2.25;
			default: 1.0;
		}
	}

	public inline function getPixelFactor():Float
	{
		return switch (this)
		{
			case FilterQuality.MEDIUM: 16.0;
			case FilterQuality.LOW: 12.0;
			case FilterQuality.RUDY: 8.0;
			default: 1.0;
		}
	}
}
