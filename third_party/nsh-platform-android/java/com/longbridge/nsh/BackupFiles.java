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

/** Encrypted backup exchange. No broad storage permission or raw URI crosses JNI. */
public final class BackupFiles {
    private static final String TAG = "com.longbridge.nsh.BackupFiles";
    private static final long MAX_IMPORT_BYTES = 128L * 1024 * 1024;
    private BackupFiles() {}

    /** Called on any thread; Android UI operations are posted to the view. */
    public static void choose(NshView view, long id, String source, String suggestedName) {
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
                results.start(id, source, suggestedName);
            } catch (RuntimeException failure) {
                complete(id, null, "无法打开系统文件选择器");
            }
        });
    }

    private static native void complete(long id, String path, String error);

    @SuppressWarnings("deprecation")
    public static final class Results extends Fragment {
        private long pending;
        private String source;

        @Override public void onCreate(Bundle state) {
            super.onCreate(state);
            setRetainInstance(true);
        }

        void start(long id, String sourcePath, String name) {
            if (pending != 0) { complete(id, null, "请先完成当前文件选择"); return; }
            pending = id;
            source = sourcePath;
            boolean exporting = sourcePath != null && !sourcePath.isEmpty();
            Intent intent = new Intent(exporting ? Intent.ACTION_CREATE_DOCUMENT : Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType(exporting ? "application/octet-stream" : "*/*");
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
            pending = 0;
            source = null;
            if (result != Activity.RESULT_OK || data == null || data.getData() == null) {
                complete(id, null, null);
                return;
            }
            Activity activity = getActivity();
            if (activity == null) { complete(id, null, "文件选择已结束，请重试"); return; }
            ContentResolver resolver = activity.getContentResolver();
            File cacheDir = activity.getCacheDir();
            Uri uri = data.getData();
            new Thread(() -> transfer(id, resolver, uri, from, cacheDir), "naviwealth-backup-file").start();
        }

        private static void transfer(long id, ContentResolver resolver, Uri uri, String source, File cacheDir) {
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
                    staging = File.createTempFile("naviwealth-import-", ".bak", cacheDir);
                    try (InputStream in = resolver.openInputStream(uri); FileOutputStream out = new FileOutputStream(staging)) {
                        if (in == null) throw new java.io.IOException();
                        copy(in, out, MAX_IMPORT_BYTES);
                        out.getFD().sync();
                    }
                    complete(id, staging.getAbsolutePath(), null);
                }
            } catch (Exception failure) {
                if (staging != null) staging.delete();
                complete(id, null, exporting ? "无法保存备份，请检查目标空间和文件权限" : "无法读取备份，请选择不超过 128 MB 的备份文件");
            }
        }

        private static void copy(InputStream in, OutputStream out, long limit) throws Exception {
            byte[] buffer = new byte[64 * 1024];
            long copied = 0;
            for (int count; (count = in.read(buffer)) != -1;) {
                copied += count;
                if (copied > limit) throw new java.io.IOException("backup too large");
                out.write(buffer, 0, count);
            }
        }
    }
}
