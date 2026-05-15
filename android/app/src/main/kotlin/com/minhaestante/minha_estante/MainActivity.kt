package com.minhaestante.minha_estante

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import com.github.junrar.Archive

class MainActivity : FlutterActivity() {
    private val channelName = "minha_estante/saf_import"
    private val archiveChannelName = "minha_estante/native_archive"
    private val pickFolderRequestCode = 8301
    private val maxArchivePages = 2000
    private val maxArchiveBytes = 1024L * 1024L * 1024L
    private val copyBufferSize = 1024 * 1024
    private val importExecutor = Executors.newSingleThreadExecutor()
    private val archiveExecutor = Executors.newSingleThreadExecutor()
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingArchiveOpen: Map<String, Any?>? = null
    private lateinit var safChannel: MethodChannel
    private lateinit var archiveChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        safChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
        safChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "syncFolder" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrBlank()) {
                        result.error("INVALID_URI", "Pasta invalida.", null)
                        return@setMethodCallHandler
                    }
                    importTreeAsync(Uri.parse(uri), result, "Nao foi possivel ler a pasta.")
                }
                else -> result.notImplemented()
            }
        }

        archiveChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            archiveChannelName
        )
        archiveChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "convertCbrToCbz" -> {
                    val uriOrPath = call.argument<String>("uri")
                        ?: call.argument<String>("path")
                    if (uriOrPath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Caminho ou URI invalido.", null)
                        return@setMethodCallHandler
                    }
                    convertCbrToCbzAsync(uriOrPath, result)
                }
                "copyArchiveUriToCache" -> {
                    val uriOrPath = call.argument<String>("uri")
                    if (uriOrPath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "URI invalida.", null)
                        return@setMethodCallHandler
                    }
                    copyArchiveUriToCacheAsync(uriOrPath, result)
                }
                "consumeInitialOpenedArchive" -> {
                    val payload = pendingArchiveOpen ?: archiveIntentPayload(intent)
                    pendingArchiveOpen = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        pendingArchiveOpen = archiveIntentPayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val payload = archiveIntentPayload(intent) ?: return
        if (::archiveChannel.isInitialized) {
            archiveChannel.invokeMethod("openArchive", payload)
        } else {
            pendingArchiveOpen = payload
        }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("PICK_IN_PROGRESS", "Ja existe uma selecao de pasta em andamento.", null)
            return
        }

        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        startActivityForResult(intent, pickFolderRequestCode)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFolderRequestCode) return

        val result = pendingPickResult
        pendingPickResult = null

        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val treeUri = data.data!!
        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

        try {
            contentResolver.takePersistableUriPermission(treeUri, flags)
            importTreeAsync(treeUri, result, "Nao foi possivel importar essa pasta.")
        } catch (error: Exception) {
            result.error(
                "IMPORT_ERROR",
                error.message ?: "Nao foi possivel importar essa pasta.",
                null
            )
        }
    }

    private fun importTreeAsync(
        treeUri: Uri,
        result: MethodChannel.Result,
        fallbackMessage: String
    ) {
        importExecutor.execute {
            try {
                val imported = importTree(treeUri)
                runOnUiThread {
                    result.success(imported)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "IMPORT_ERROR",
                        error.message ?: fallbackMessage,
                        null
                    )
                }
            }
        }
    }

    private fun importTree(treeUri: Uri): Map<String, Any> {
        val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootDocumentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocumentId)
        val folderName = queryDisplayName(rootDocumentUri)
            ?: rootDocumentId.substringAfterLast(":").ifBlank { "Pasta local" }

        val targetRoot = File(filesDir, "local_library/${sha1(treeUri.toString())}")
        targetRoot.mkdirs()

        val files = mutableListOf<Map<String, Any?>>()
        val totalFiles = countSupportedFiles(treeUri, rootDocumentId)
        val importedCount = intArrayOf(0)
        emitProgress(0, totalFiles, null, "start")
        scanDocumentTree(
            treeUri = treeUri,
            documentId = rootDocumentId,
            targetDirectory = targetRoot,
            relativePrefix = "",
            totalFiles = totalFiles,
            importedCount = importedCount,
            files = files
        )
        emitProgress(totalFiles, totalFiles, null, "done")

        return mapOf(
            "uri" to treeUri.toString(),
            "name" to folderName,
            "files" to files
        )
    }

    private fun scanDocumentTree(
        treeUri: Uri,
        documentId: String,
        targetDirectory: File,
        relativePrefix: String,
        totalFiles: Int,
        importedCount: IntArray,
        files: MutableList<Map<String, Any?>>
    ) {
        targetDirectory.mkdirs()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_SIZE
        )

        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)

            while (cursor.moveToNext()) {
                val childId = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex) ?: continue
                val mimeType = cursor.getString(mimeIndex)
                val modifiedMillis = if (modifiedIndex >= 0) cursor.getLong(modifiedIndex) else 0L
                val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L

                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val childRelativePrefix = if (relativePrefix.isBlank()) {
                        name
                    } else {
                        "$relativePrefix/$name"
                    }
                    scanDocumentTree(
                        treeUri = treeUri,
                        documentId = childId,
                        targetDirectory = File(targetDirectory, sanitize(name)),
                        relativePrefix = childRelativePrefix,
                        totalFiles = totalFiles,
                        importedCount = importedCount,
                        files = files
                    )
                    continue
                }

                if (!isSupported(name)) continue

                val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                val outputFile = File(targetDirectory, sanitize(name))
                val relativePath = if (relativePrefix.isBlank()) name else "$relativePrefix/$name"
                copyDocument(documentUri, outputFile, size, modifiedMillis)

                files.add(
                    mapOf(
                        "name" to name,
                        "path" to outputFile.absolutePath,
                        "relativePath" to relativePath,
                        "sourceUri" to documentUri.toString(),
                        "modifiedMillis" to modifiedMillis,
                        "size" to size
                    )
                )
                importedCount[0] = importedCount[0] + 1
                emitProgress(importedCount[0], totalFiles, name, "importing")
            }
        }
    }

    private fun countSupportedFiles(treeUri: Uri, documentId: String): Int {
        var count = 0
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )

        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

            while (cursor.moveToNext()) {
                val childId = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex) ?: continue
                val mimeType = cursor.getString(mimeIndex)

                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    count += countSupportedFiles(treeUri, childId)
                } else if (isSupported(name)) {
                    count += 1
                }
            }
        }

        return count
    }

    private fun emitProgress(current: Int, total: Int, fileName: String?, phase: String) {
        runOnUiThread {
            safChannel.invokeMethod(
                "importProgress",
                mapOf(
                    "current" to current,
                    "total" to total,
                    "fileName" to fileName,
                    "phase" to phase
                )
            )
        }
    }

    private fun copyDocument(sourceUri: Uri, outputFile: File, size: Long, modifiedMillis: Long) {
        if (outputFile.exists() && size > 0 && outputFile.length() == size) {
            return
        }

        outputFile.parentFile?.mkdirs()
        contentResolver.openInputStream(sourceUri).use { input ->
            if (input == null) throw IllegalStateException("Nao foi possivel abrir o arquivo.")
            outputFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        if (modifiedMillis > 0) {
            outputFile.setLastModified(modifiedMillis)
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            if (cursor.moveToFirst() && nameIndex >= 0) {
                return cursor.getString(nameIndex)
            }
        }
        return null
    }

    private fun isSupported(name: String): Boolean {
        val lower = name.lowercase(Locale.ROOT)
        return lower.endsWith(".pdf") ||
            lower.endsWith(".epub") ||
            lower.endsWith(".cbr") ||
            lower.endsWith(".cb7") ||
            lower.endsWith(".cbt") ||
            lower.endsWith(".cba") ||
            lower.endsWith(".azw3") ||
            lower.endsWith(".kfx") ||
            lower.endsWith(".mobi") ||
            lower.endsWith(".doc") ||
            lower.endsWith(".docx") ||
            lower.endsWith(".txt") ||
            lower.endsWith(".mp3") ||
            lower.endsWith(".m4a") ||
            lower.endsWith(".aac") ||
            lower.endsWith(".cbz")
    }

    private fun sanitize(value: String): String {
        return value.replace(Regex("""[\\/:*?"<>|]"""), "_").ifBlank { "arquivo" }
    }

    private fun sha1(value: String): String {
        val bytes = MessageDigest.getInstance("SHA-1").digest(value.toByteArray())
        return bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private class ArchiveConversionException(message: String) : Exception(message)

    private fun isImageFile(name: String): Boolean {
        val lower = name.lowercase(Locale.ROOT)
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".png") || lower.endsWith(".webp") ||
            lower.endsWith(".gif")
    }

    private fun normalizeArchivePath(name: String): String {
        return name.replace("\\", "/").trim()
    }

    private fun isUnsafeArchivePath(name: String): Boolean {
        val normalized = normalizeArchivePath(name)
        if (normalized.startsWith("/")) return true
        if (Regex("^[A-Za-z]:").containsMatchIn(normalized)) return true
        return normalized.split("/").any { it == ".." }
    }

    private fun isIgnoredArchiveEntry(name: String): Boolean {
        val normalized = normalizeArchivePath(name)
        val parts = normalized.split("/")
        val leaf = parts.lastOrNull()?.lowercase(Locale.ROOT) ?: return true
        return parts.any { it.equals("__MACOSX", ignoreCase = true) } ||
            leaf == ".ds_store" ||
            leaf == "thumbs.db"
    }

    private fun safeZipEntryName(name: String, index: Int): String {
        val leaf = normalizeArchivePath(name).substringAfterLast("/")
        val safeLeaf = sanitize(leaf)
        return "%04d_%s".format(Locale.ROOT, index, safeLeaf)
    }

    private fun safeBaseName(name: String): String {
        return sanitize(name)
            .replace(Regex("""\.[^.]+$"""), "")
            .take(48)
            .ifBlank { "converted" }
    }

    private fun isHeaderEncrypted(header: Any): Boolean {
        return listOf("isEncrypted", "getEncrypted").any { methodName ->
            try {
                header.javaClass.getMethod(methodName).invoke(header) == true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun naturalCompare(a: String, b: String): Int {
        val regex = Regex("\\d+")
        val matchA = regex.findAll(a).toList()
        val matchB = regex.findAll(b).toList()

        var i = 0
        while (i < matchA.size && i < matchB.size) {
            val numA = matchA[i].value.toLongOrNull() ?: 0
            val numB = matchB[i].value.toLongOrNull() ?: 0
            if (numA != numB) {
                return numA.compareTo(numB)
            }
            i++
        }
        return a.compareTo(b)
    }

    private fun convertCbrToCbzAsync(uriOrPath: String, result: MethodChannel.Result) {
        archiveExecutor.execute {
            var fileToProcess: File? = null
            var temporaryInput: File? = null
            var destCbz: File? = null

            try {
                val isContentUri = uriOrPath.startsWith("content://")
                fileToProcess = if (isContentUri) {
                    copyContentUriToCacheFile(Uri.parse(uriOrPath)).also { temporaryInput = it }
                } else if (uriOrPath.startsWith("file://")) {
                    File(Uri.parse(uriOrPath).path ?: "")
                } else {
                    File(uriOrPath)
                }

                validateArchiveInput(fileToProcess)

                val outputDir = File(cacheDir, "native_archive").apply { mkdirs() }
                destCbz = File.createTempFile(
                    "${safeBaseName(fileToProcess.name)}_",
                    ".cbz",
                    outputDir
                )

                convertRarFileToCbz(fileToProcess, destCbz)
                temporaryInput?.delete()

                runOnUiThread {
                    result.success(destCbz.absolutePath)
                }
            } catch (error: Throwable) {
                temporaryInput?.delete()
                destCbz?.delete()

                val finalMsg = conversionErrorMessage(error, fileToProcess)
                val details = mapOf(
                    "cause" to error.javaClass.simpleName,
                    "rawMessage" to (error.message ?: "")
                )

                runOnUiThread {
                    result.error("CONVERSION_FAILED", finalMsg, details)
                }
            }
        }
    }

    private fun copyArchiveUriToCacheAsync(uriOrPath: String, result: MethodChannel.Result) {
        archiveExecutor.execute {
            try {
                val file = if (uriOrPath.startsWith("content://")) {
                    copyContentUriToCacheFile(Uri.parse(uriOrPath))
                } else if (uriOrPath.startsWith("file://")) {
                    File(Uri.parse(uriOrPath).path ?: "")
                } else {
                    File(uriOrPath)
                }

                validateArchiveInput(file)
                runOnUiThread { result.success(file.absolutePath) }
            } catch (error: Throwable) {
                val finalMsg = conversionErrorMessage(error, null)
                runOnUiThread {
                    result.error(
                        "COPY_FAILED",
                        finalMsg,
                        mapOf(
                            "cause" to error.javaClass.simpleName,
                            "rawMessage" to (error.message ?: "")
                        )
                    )
                }
            }
        }
    }

    private fun validateArchiveInput(file: File) {
        if (!file.exists()) {
            throw ArchiveConversionException("Arquivo CBR não encontrado no caminho especificado.")
        }
        if (!file.isFile || !file.canRead()) {
            throw ArchiveConversionException("Não foi possível ler este CBR.")
        }
        if (file.length() <= 0L) {
            throw ArchiveConversionException("Este CBR está vazio ou inválido.")
        }
        if (file.length() > maxArchiveBytes) {
            throw ArchiveConversionException("Este CBR excede o limite de 1 GB.")
        }
    }

    private fun copyContentUriToCacheFile(uri: Uri): File {
        val displayName = queryOpenableDisplayName(uri) ?: "arquivo.cbr"
        val extension = displayName.substringAfterLast(".", "cbr")
            .replace(Regex("[^A-Za-z0-9]"), "")
            .ifBlank { "cbr" }
            .take(8)
        val outputDir = File(cacheDir, "native_archive").apply { mkdirs() }
        val outputFile = File.createTempFile("incoming_archive_", ".$extension", outputDir)

        try {
            val input = contentResolver.openInputStream(uri)
                ?: throw ArchiveConversionException("Não foi possível abrir este CBR.")

            val copiedBytes = input.use { source ->
                FileOutputStream(outputFile).use { target ->
                    copyLimited(source, target)
                }
            }

            if (copiedBytes <= 0L) {
                throw ArchiveConversionException("Este CBR está vazio ou inválido.")
            }
        } catch (error: Throwable) {
            outputFile.delete()
            throw error
        }

        return outputFile
    }

    private fun copyLimited(source: InputStream, target: OutputStream): Long {
        var total = 0L
        val buffer = ByteArray(copyBufferSize)

        BufferedInputStream(source, copyBufferSize).use { bufferedSource ->
            BufferedOutputStream(target, copyBufferSize).use { bufferedTarget ->
                while (true) {
                    val read = bufferedSource.read(buffer)
                    if (read == -1) break

                    total += read.toLong()
                    if (total > maxArchiveBytes) {
                        throw ArchiveConversionException("Este CBR excede o limite de 1 GB.")
                    }

                    bufferedTarget.write(buffer, 0, read)
                }
            }
        }

        return total
    }

    private fun convertRarFileToCbz(sourceFile: File, destCbz: File) {
        var processedBytes = 0L
        var imageCount = 0

        Archive(sourceFile).use { archive ->
            if (archive.isEncrypted) {
                throw ArchiveConversionException("Este CBR está protegido por senha e não pode ser convertido.")
            }

            val sortedHeaders = archive.fileHeaders.sortedWith(Comparator { h1, h2 ->
                val name1 = h1.fileNameString ?: ""
                val name2 = h2.fileNameString ?: ""
                naturalCompare(name1, name2)
            })

            ZipOutputStream(
                BufferedOutputStream(FileOutputStream(destCbz), copyBufferSize)
            ).use { zos ->
                for (header in sortedHeaders) {
                    if (header.isDirectory) continue
                    if (isHeaderEncrypted(header)) {
                        throw ArchiveConversionException("Este CBR está protegido por senha e não pode ser convertido.")
                    }

                    val rawName = header.fileNameString ?: continue
                    val normalizedName = normalizeArchivePath(rawName)
                    if (isUnsafeArchivePath(normalizedName)) continue
                    if (isIgnoredArchiveEntry(normalizedName)) continue

                    val leafName = normalizedName.substringAfterLast("/")
                    if (!isImageFile(leafName)) continue

                    if (imageCount >= maxArchivePages) {
                        throw ArchiveConversionException("Este CBR excede o limite de $maxArchivePages páginas.")
                    }

                    imageCount += 1
                    val zipEntry = ZipEntry(safeZipEntryName(leafName, imageCount))
                    zos.putNextEntry(zipEntry)

                    val limitedOutput = object : OutputStream() {
                        override fun write(b: Int) {
                            processedBytes += 1
                            ensureWithinLimit()
                            zos.write(b)
                        }

                        override fun write(b: ByteArray, off: Int, len: Int) {
                            processedBytes += len.toLong()
                            ensureWithinLimit()
                            zos.write(b, off, len)
                        }

                        private fun ensureWithinLimit() {
                            if (processedBytes > maxArchiveBytes) {
                                throw ArchiveConversionException("Este CBR excede o limite de 1 GB.")
                            }
                        }
                    }

                    try {
                        archive.extractFile(header, limitedOutput)
                    } finally {
                        zos.closeEntry()
                    }
                }
            }
        }

        if (imageCount == 0) {
            throw ArchiveConversionException("Nenhuma imagem compatível foi encontrada no CBR.")
        }
    }

    private fun conversionErrorMessage(error: Throwable, sourceFile: File?): String {
        if (error is ArchiveConversionException) {
            return error.message ?: "Não foi possível converter este CBR. Tente converter manualmente para CBZ."
        }

        val raw = error.message ?: ""
        if (raw.contains("password", ignoreCase = true) ||
            raw.contains("senha", ignoreCase = true) ||
            raw.contains("encrypted", ignoreCase = true)
        ) {
            return "Este CBR está protegido por senha e não pode ser convertido."
        }

        if (sourceFile != null && isRar5File(sourceFile)) {
            return "Não foi possível converter este CBR. Tente converter manualmente para CBZ."
        }

        return "Não foi possível converter este CBR. Tente converter manualmente para CBZ."
    }

    private fun isRar5File(file: File): Boolean {
        return try {
            val signature = ByteArray(8)
            file.inputStream().use { input ->
                if (input.read(signature) < signature.size) return false
            }
            signature.contentEquals(
                byteArrayOf(
                    0x52.toByte(),
                    0x61.toByte(),
                    0x72.toByte(),
                    0x21.toByte(),
                    0x1A.toByte(),
                    0x07.toByte(),
                    0x01.toByte(),
                    0x00.toByte()
                )
            )
        } catch (_: Exception) {
            false
        }
    }

    private fun queryOpenableDisplayName(uri: Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (cursor.moveToFirst() && nameIndex >= 0) {
                return cursor.getString(nameIndex)
            }
        }
        return null
    }

    private fun archiveIntentPayload(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW && intent.action != Intent.ACTION_SEND) {
            return null
        }

        val uri = intent.data
            ?: intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            ?: return null
        val name = queryOpenableDisplayName(uri)
            ?: uri.lastPathSegment?.substringAfterLast("/")
            ?: "arquivo.cbr"
        val mimeType = intent.type

        if (!looksLikeArchive(name, mimeType, uri.toString())) {
            return null
        }

        return mapOf(
            "uri" to uri.toString(),
            "name" to name,
            "mimeType" to mimeType
        )
    }

    private fun looksLikeArchive(name: String, mimeType: String?, uri: String): Boolean {
        val lowerName = name.lowercase(Locale.ROOT)
        val lowerUri = uri.lowercase(Locale.ROOT)
        val supportedExtension = listOf(".cbr", ".rar", ".cbz", ".zip").any {
            lowerName.endsWith(it) || lowerUri.endsWith(it)
        }
        if (supportedExtension) return true

        val lowerMime = mimeType?.lowercase(Locale.ROOT) ?: return false
        return lowerMime in setOf(
            "application/x-cbr",
            "application/vnd.comicbook-rar",
            "application/x-rar",
            "application/x-rar-compressed",
            "application/vnd.rar",
            "application/x-cbz",
            "application/vnd.comicbook+zip",
            "application/zip"
        )
    }
}
