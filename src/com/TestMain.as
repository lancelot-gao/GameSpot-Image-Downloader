package com 
{
	import com.spotlightor.filesystem.JpegAsyncFileSaver;
	import com.spotlightor.filesystem.saveImage;
	import com.spotlightor.filesystem.JpegAsyncFileSaver;
	import com.spotlightor.loading.QueueLoader;
	import com.spotlightor.loading.SmartLoader;
	import com.spotlightor.utils.DisplayUtils;
	import com.spotlightor.utils.Log;
	import com.spotlightor.utils.StringUtils;
	import fl.controls.Button;
	import flash.display.Bitmap;
	import flash.display.DisplayObject;
	import flash.display.InteractiveObject;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.MouseEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.geom.Rectangle;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.text.TextField;
	import flash.utils.setTimeout;
	/**
	 * ...
	 * @author Gao Ming (Spotlightor Interactive)
	 */
	public class TestMain extends Sprite
	{
		private var _imageGalleryBaseURL	:String;
		private var _numPages				:int;
		private var _numImages				:int;
		private var _numError				:int;
		private var _imageURLs				:Vector.<String>;
		
		private var _pageLoader				:QueueLoader;
		private var _imageLoader			:SmartLoader;
		private var _imageSaveFolder		:File;
		private var _imageSaving			:Bitmap;
		
		private function get buttonLoad():Button { return getChildByName('bt_load') as Button; }
		private function get tfURL():TextField { return getChildByName('tf_url') as TextField; }
		private function get imageArea():DisplayObject { return getChildByName('mc_image'); }
		private function get tfStats():TextField { return this.tf_stats; }
		
		public function TestMain() 
		{
			buttonLoad.addEventListener(MouseEvent.CLICK, onClickButtonLoad);
			
			tfURL.addEventListener(MouseEvent.CLICK, onClickUrl);
			tfURL.addEventListener(Event.CHANGE, onUrlTextChanged);
		}
		
		private function onClickUrl(e:MouseEvent):void 
		{
			tfURL.setSelection(0, tfURL.text.length-1);
		}
		
		private function onUrlTextChanged(e:Event):void 
		{
			var newImageGalleryBaseURL = getGalleryPageBaseURL(tfURL.text);
			if (_imageGalleryBaseURL != newImageGalleryBaseURL) {
				_imageGalleryBaseURL = newImageGalleryBaseURL;
				buttonLoad.label = "Load";
				buttonLoad.enabled = true;
			}
		}
		
		private function onClickButtonLoad(e:MouseEvent):void 
		{
			if(tfURL.text != ""){
				var url:String = tfURL.text;
				_imageGalleryBaseURL = getGalleryPageBaseURL(url);
				
				startAnalyzingUrl();
			}
		}
		
		private function getGalleryPageBaseURL(pageURL:String):String
		{
			var indexOfQuestion:int = pageURL.lastIndexOf('?');
			if (indexOfQuestion == -1) return pageURL;
			else return pageURL.substring(0, indexOfQuestion);
		}
		
		private function startAnalyzingUrl()
		{
			var loader:URLLoader = new URLLoader(new URLRequest(_imageGalleryBaseURL));
			loader.addEventListener(Event.COMPLETE, onUrlLoaded);
			Log.status(this, "Gallery page base url:", _imageGalleryBaseURL);
			Log.status(this, "Start loading url page");
			
			buttonLoad.enabled = false;
			updateStatsOnButtonLabel("Downloading");
			updateStatsText("Analyzing Page Number");
		}
		
		private function onUrlLoaded(e:Event):void 
		{
			Log.status(this, "url page loaded");
			var html:String = (e.target as URLLoader).data;
			
			_numPages = getNumPagesFromHTML(html);
			Log.status(this, "Num pages of gallery:", _numPages);
			
			_pageLoader = new QueueLoader();
			_pageLoader.add(_imageGalleryBaseURL, 1, null, 'page0');
			for (var i:int = 1; i < _numPages; i++) 
			{
				_pageLoader.add(_imageGalleryBaseURL +'?page='+ i.toString(), 1, null, 'page' + i.toString());
			}
			_pageLoader.addEventListener(Event.COMPLETE, onGalleryPagesLoaded);
			_pageLoader.startLoading();
			
			updateStatsText("Page Number"+_numPages.toString());
			updateStatsText("Loading Image Urls");
		}
		
		private function getNumPagesFromHTML(html:String):int
		{
			var numPages = 1;
			var numKeywords = 0;
			var searchStartIndex = html.indexOf('images/?page=');
			while (searchStartIndex != -1) {
				numKeywords++;
				searchStartIndex = html.indexOf('images/?page=', searchStartIndex + 1);
			}
			if (numKeywords >= 2) numPages = numKeywords - 1;
			return numPages;
		}
		
		private function onGalleryPagesLoaded(e:Event):void 
		{
			var pages:Array = _pageLoader.getContentsArray();
			updateStatsText("Analyzing Image Urls");
			
			_imageURLs = new Vector.<String>();
			for each (var item:String in pages) 
			{
				var pageImageURLs:Vector.<String> = getImageURLsFromPageHTML(item);
				if (pageImageURLs) {
					for (var i:int = 0; i < pageImageURLs.length; i++){
						if (_imageURLs.indexOf(pageImageURLs[i]) == -1)
							_imageURLs.push(pageImageURLs[i]);
					}
				}
			}
			_numImages = _imageURLs.length;
			updateStatsText('Num images:'+ _imageURLs.length);
			
			if (!buttonLoad.enabled) buttonLoad.label = "Downloading";
			
			if (_imageURLs)
			{
				_imageSaveFolder = File.desktopDirectory;
				_imageSaveFolder.browseForDirectory('请选择保存图片的文件夹');
				_imageSaveFolder.addEventListener(Event.SELECT, onSaveFolderSelected);
			}
		}
		
		private function getImageURLsFromPageHTML(pageHTML:String):Vector.<String>
		{
			var regExp:RegExp = /http:\/\/[a-z0-9\/\.\-_%]*gum[0-9]*\.jpg/gi;
			var gumImages:Array = pageHTML.match(regExp);
			var screenImages:Vector.<String> = new Vector.<String>();
			for each (var item:String in gumImages) 
			{
				var indexOfGum:int = item.lastIndexOf('gum');
				var screenImageURL:String = item.substr(0, indexOfGum) + 'screen' + item.substr(indexOfGum + 3);
				screenImages.push(screenImageURL);
			}
			return screenImages;
		}
		
		private function onSaveFolderSelected(e:Event):void 
		{
			Log.status(this, "Save folder selected:", _imageSaveFolder.url);
			
			_numError = 0;
			loadFirstImage();
		}
		
		private function loadFirstImage():void
		{
			var imageName:String = _imageURLs[0].substr(_imageURLs[0].lastIndexOf('\/') + 1);
			var imageFile:File = _imageSaveFolder.resolvePath(imageName);
			if (imageFile.exists == false)
			{
				_imageLoader = new SmartLoader(_imageURLs[0], _imageURLs[0], null);
				_imageLoader.addEventListener(Event.COMPLETE, onImageLoaded);
				_imageLoader.addEventListener(IOErrorEvent.IO_ERROR, onImageLoadingError);
				_imageLoader.startLoading();
				var loadingImageIndex = _numImages - _imageURLs.length + 1;
				var statsMessage = "Loading ";
				statsMessage += StringUtils.toFixedInt(loadingImageIndex, _numImages.toString().length) + "/" + _numImages.toString();
				statsMessage += " " + _numError.toString() + " errors";
				statsMessage += "\n" + _imageURLs[0];
				updateStatsText(statsMessage);
			}
			else
			{
				shiftAndTryLoadingNextImage();
			}
		}
		
		private function onImageLoadingError(e:IOErrorEvent):void 
		{
			_numError++;
			Log.status(this, 'Image error', e);
			shiftAndTryLoadingNextImage();
		}
		
		private function onImageLoaded(e:Event):void 
		{
			Log.status(this, 'Image loaded:', _imageLoader.url);
			
			var image:Bitmap = _imageLoader.content;
			if (image) {
				image.smoothing = true;
				
				addChild(image);			
				DisplayUtils.fitInArea(image, imageArea.getRect(this), DisplayUtils.FIT_IMAGE);
				
				saveLoaderImage();
			}
		}
		
		private function saveLoaderImage():void
		{
			if (_imageLoader && _imageLoader.content is Bitmap)
			{
				if (_imageSaving) 
				{
					if (_imageSaving.parent) _imageSaving.parent.removeChild(_imageSaving);
					_imageSaving.bitmapData.dispose();
					_imageSaving = null;
				}
				
				var image:Bitmap = _imageLoader.content;
				_imageSaving = image;
				var imageName:String = _imageLoader.url.substr(_imageLoader.url.lastIndexOf('\/') + 1);
				var imageFile:File = _imageSaveFolder.resolvePath(imageName);
				if (!imageFile.exists)
				{
					Log.status(this, 'Start saving image:', imageFile.url);
					var saver:JpegAsyncFileSaver = new JpegAsyncFileSaver(90);
					saver.addEventListener(Event.COMPLETE, onImageSaved);
					saver.saveJpegImage(image.bitmapData, imageFile);
				}
				else 
				{
					Log.warning(this, 'Image file already exist:', imageFile.url);
					shiftAndTryLoadingNextImage();
				}
			}
		}
		
		private function onImageSaved(e:Event):void 
		{
			Log.debug(this, "Save complte");
			shiftAndTryLoadingNextImage();
		}
		
		private function shiftAndTryLoadingNextImage():void
		{
			
			_imageURLs.shift();
			
			if (_imageURLs.length > 0) {
				loadFirstImage();
			}
			else {
				updateStatsOnButtonLabel("Complete");
				updateStatsText((_numImages - _numError).toString() + " images loaded, "+_numError.toString()+" errors");
			}
		}
		
		private function updateStatsOnButtonLabel(label:String):void
		{
			if (!buttonLoad.enabled) buttonLoad.label = label;
		}
		
		private function updateStatsText(message:String):void
		{
			tfStats.text = message;
			Log.status(this, message);
		}
	}

}