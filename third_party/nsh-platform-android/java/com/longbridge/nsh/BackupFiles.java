package com.longbridge.nsh;

import android.app.Activity;
import android.app.Fragment;
import android.content.ContentResolver;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

/** Purpose-limited document exchange. No broad storage permission or raw URI crosses JNI. */
public final class BackupFiles {
    private static final String TAG = "com.longbridge.nsh.BackupFiles";
    private static final long MAX_IMPORT_BYTES = 128L * 1024 * 1024;
    private BackupFiles() {}

    /** Called on any thread; Android UI operations are posted to the view. */
    public static void choose(NshView view, long id, String source, String suggestedName) {
        chooseDocument(view, id, source, suggestedName, "备份", "*/*", MAX_IMPORT_BYTES, ".bak");
    }

    /** A bounded typed import, separate from the encrypted-backup contract. */
    public static void chooseImport(NshView view, long id, String purpose, String mimeType, long maxBytes, String suffix) {
        if (maxBytes <= 0 || maxBytes > MAX_IMPORT_BYTES || !"text/csv".equals(mimeType) || !".csv".equals(suffix)) {
            complete(id, null, "不支持此文件导入类型");
            return;
        }
        chooseDocument(view, id, "", "", purpose, mimeType, maxBytes, suffix);
    }

    private static void chooseDocument(NshView view, long id, String source, String suggestedName, String purpose, String mimeType, long maxBytes, String suffix) {
        view.post(() -> {
            Activity activity = SystemUi.activity(view.getContext());
            if (activity == null || activity.isFinishing()) {
                complete(id, null, "当前界面无法打开文件选择器");
                return;
            }
            try {
                android.app.FragmentManager manager = activity.getFragmentManager();
                Results results = (Results) manager.findFragmentByTag(TAG);
                if (results == null) {
                    results = new Results();
                    manager.beginTransaction().add(results, TAG).commitNow();
                }
                results.start(id, source, suggestedName, purpose, mimeType, maxBytes, suffix);
            } catch (RuntimeException failure) {
                complete(id, null, "无法打开系统文件选择器");
            }
        });
    }

    // A false acknowledgement means Rust abandoned the request; Java removes
    // any staging file rather than leaving private financial data behind.
    private static native boolean complete(long id, String path, String error);

    @SuppressWarnings("deprecation")
    public static final class Results extends Fragment {
        private long pending;
        private String source;
        private String purpose;
        private long maxBytes;
        private String suffix;

        @Override public void onCreate(Bundle state) {
            super.onCreate(state);
            setRetainInstance(true);
        }

        void start(long id, String sourcePath, String name, String importPurpose, String mimeType, long limit, String importSuffix) {
            if (pending != 0) { complete(id, null, "请先完成当前文件选择"); return; }
            pending = id;
            source = sourcePath;
            purpose = importPurpose;
            maxBytes = limit;
            suffix = importSuffix;
            boolean exporting = sourcePath != null && !sourcePath.isEmpty();
            Intent intent = new Intent(exporting ? Intent.ACTION_CREATE_DOCUMENT : Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType(exporting ? "application/octet-stream" : mimeType);
            if (!exporting && "text/csv".equals(mimeType)) {
                intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {"text/csv", "text/comma-separated-values", "application/csv", "text/plain", "application/vnd.ms-excel", "application/octet-stream"});
            }
            if (exporting) intent.putExtra(Intent.EXTRA_TITLE, name);
            try { startActivityForResult(intent, 0x4f01); }
            catch (RuntimeException failure) {
                pending = 0;
                complete(id, null, "设备没有可用的文件选择器");
            }
        }

        @Override public void onActivityResult(int code, int result, Intent data) {
            if (code != 0x4f01 || pending == 0) { super.onActivityResult(code, result, data); return; }
            long id = pending;
            String from = source;
            String importPurpose = purpose;
            long limit = maxBytes;
            String importSuffix = suffix;
            pending = 0;
            source = null;
            purpose = null;
            suffix = null;
            if (result != Activity.RESULT_OK || data == null || data.getData() == null) {
                complete(id, null, null);
                return;
            }
            Activity activity = getActivity();
            if (activity == null) { complete(id, null, "文件选择已结束，请重试"); return; }
            ContentResolver resolver = activity.getContentResolver();
            File cacheDir = activity.getCacheDir();
            Uri uri = data.getData();
            new Thread(() -> transfer(id, resolver, uri, from, cacheDir, importPurpose, limit, importSuffix), "naviwealth-document-file").start();
        }

        private static void transfer(long id, ContentResolver resolver, Uri uri, String source, File cacheDir, String purpose, long limit, String suffix) {
            boolean exporting = source != null && !source.isEmpty();
            File staging = null;
            try {
                if (exporting) {
                    try (InputStream in = new FileInputStream(source); OutputStream out = resolver.openOutputStream(uri, "wt")) {
                        if (out == null) throw new java.io.IOException();
                        copy(in, out, Long.MAX_VALUE);
                        out.flush();
                    }
                    complete(id, source, null);
                } else {
                    staging = File.createTempFile("naviwealth-import-", suffix, cacheDir);
                    try (InputStream in = resolver.openInputStream(uri); FileOutputStream out = new FileOutputStream(staging)) {
                        if (in == null) throw new java.io.IOException();
                        copy(in, out, limit);
                        out.getFD().sync();
                    }
                    if (!complete(id, staging.getAbsolutePath(), null)) staging.delete();
                }
            } catch (Exception failure) {
                if (staging != null) staging.delete();
                complete(id, null, exporting ? "无法保存备份，请检查目标空间和文件权限" : "CSV账单".equals(purpose) ? "无法读取 CSV，请选择不超过 10 MB 的 UTF-8 账单文件" : "无法读取备份，请选择不超过 128 MB 的备份文件");
            }
        }

        private static void copy(InputStream in, OutputStream out, long limit) throws Exception {
            byte[] buffer = new byte[64 * 1024];
            long copied = 0;
            for (int count; (count = in.read(buffer)) != -1;) {
                copied += count;
                if (copied > limit) throw new java.io.IOException("document size limit");
                out.write(buffer, 0, count);
            }
        }
    }
}
