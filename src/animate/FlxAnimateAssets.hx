package animate;

import flixel.FlxG;
import haxe.io.Bytes;
import haxe.io.Path;
import openfl.display.BitmapData;

using StringTools;

/**
 * Wrapper for assets to allow HaxeFlixel 5.9.0+ and HaxeFlixel 5.8.0- compatibility.
 * Class to be used for replacing the method used for loading assets, if using ``FlxAnimateFrames.fromAnimate`` through a folder path.
 * For more control over loading texture atlases I recommend using the rest of the params in the ``fromAnimate`` frame loader.
 */
class FlxAnimateAssets
{
	public static dynamic function exists(path:String, type:AssetType):Bool
	{
		// Check openfl/flixel assets first
		#if (flixel >= "5.9.0")
		if (FlxG.assets.exists(path, type))
			return true;
		#else
		if (openfl.utils.Assets.exists(path, type))
			return true;
		#end

		// Fallback to filesystem
		#if sys
		return sys.FileSystem.exists(Path.normalize(path));
		#end

		return false;
	}

	public static dynamic function getText(path:String):String
	{
		// Check openfl/flixel assets first
		#if (flixel >= "5.9.0")
		if (FlxG.assets.exists(path, AssetType.TEXT))
			return FlxG.assets.getText(path);
		#else
		if (openfl.utils.Assets.exists(path, AssetType.TEXT))
			return openfl.utils.Assets.getText(path);
		#end

		// Fallback to filesystem
		#if sys
		var normalizedPath = Path.normalize(path);
		if (sys.FileSystem.exists(normalizedPath))
			return sys.io.File.getContent(normalizedPath);
		#end

		return null;
	}

	public static dynamic function getBytes(path:String):Bytes
	{
		// Check openfl/flixel assets first
		#if (flixel >= "5.9.0")
		if (FlxG.assets.exists(path, AssetType.BINARY))
			return FlxG.assets.getBytes(path);
		#else
		if (openfl.utils.Assets.exists(path, AssetType.BINARY))
			return openfl.utils.Assets.getBytes(path);
		#end

		// Fallback to filesystem
		#if sys
		var normalizedPath = Path.normalize(path);
		if (sys.FileSystem.exists(normalizedPath))
			return sys.io.File.getBytes(normalizedPath);
		#end

		return null;
	}

	public static dynamic function getBitmapData(path:String):BitmapData
	{
		// Check openfl/flixel assets first
		#if (flixel >= "5.9.0")
		if (FlxG.assets.exists(path, AssetType.IMAGE))
			return FlxG.assets.getBitmapData(path);
		#else
		if (openfl.utils.Assets.exists(path, AssetType.IMAGE))
			return openfl.utils.Assets.getBitmapData(path);
		#end

		// Fallback to filesystem
		#if sys
		var normalizedPath = Path.normalize(path);
		if (sys.FileSystem.exists(normalizedPath))
			return BitmapData.fromFile(normalizedPath);
		#end

		return null;
	}

	public static dynamic function list(path:String, ?type:AssetType, ?library:String, includeSubDirectories:Bool = false):Array<String>
	{
		var result:Array<String> = null;

		// Check openfl/flixel assets first
		result = #if (flixel >= "5.9.0") FlxG.assets.list(type); #else openfl.utils.Assets.list(type); #end

		if (result == null)
			result = [];

		// Fallback to filesystem for non-library assets
		#if sys
		if (library == null || library.length == 0)
		{
			var normalizedPath = Path.normalize(path);
			if (sys.FileSystem.exists(normalizedPath) && sys.FileSystem.isDirectory(normalizedPath))
			{
				var files:Array<String> = sys.FileSystem.readDirectory(normalizedPath);
				var sysResult:Array<String> = [];
				var checkSubDirectory:String->Void = null;

				checkSubDirectory = (file) ->
				{
					var fullPath = Path.join([normalizedPath, file]);
					if (sys.FileSystem.exists(fullPath) && sys.FileSystem.isDirectory(fullPath) && includeSubDirectories)
					{
						var subFiles = sys.FileSystem.readDirectory(fullPath).map((subFile) -> Path.join([file, subFile]));
						for (sf in subFiles)
							checkSubDirectory(sf);
					}
					else
					{
						sysResult.push(Path.normalize(file));
					}
				};

				for (file in files)
					checkSubDirectory(file);

				return sysResult;
			}
		}
		#end

		// Safely extract the asset directory search path, stripping potential OpenFL asset library prefix identifiers
		var assetSearchPath = path.contains(":") ? path.substring(path.indexOf(':') + 1) : path;
		assetSearchPath = Path.normalize(assetSearchPath);

		// Ensure the search pattern closes out cleanly with a trailing slash for strict directory mapping
		var searchPattern = assetSearchPath;
		if (!searchPattern.endsWith("/")) 
			searchPattern += "/";

		// Get only the files actually contained inside the Texture Atlas folder
		// Plus cross-platform formatting to guarantee clean directory returns
		var filteredResult = result.filter((str) -> {
			var normalizedStr = Path.normalize(str);
			return normalizedStr.startsWith(assetSearchPath);
		});

		return filteredResult.map((str) -> {
			var normalizedStr = Path.normalize(str);
			if (normalizedStr.startsWith(searchPattern)) {
				return normalizedStr.substring(searchPattern.length);
			}
			return Path.withoutDirectory(normalizedStr);
		});
	}
}

typedef AssetType = #if (flixel >= "5.9.0") flixel.system.frontEnds.AssetFrontEnd.FlxAssetType #else openfl.utils.AssetType #end;
