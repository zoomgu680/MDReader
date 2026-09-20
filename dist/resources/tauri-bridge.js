// Tauri Bridge - 桥接原生能力
// 仅在 Tauri 环境下生效，浏览器下静默退化为纯 Web 行为
(function() {
  const isTauri = typeof window.__TAURI__ !== 'undefined' || typeof window.__TAURI_IPC__ !== 'undefined';

  if (!isTauri) {
    // 浏览器模式：占位，让现有代码不受影响
    window.__TAURI_BRIDGE__ = {
      mode: 'browser',
      currentFilePath: '',
      loadByPath: () => {},
      openFile: () => Promise.resolve(null),
      saveFile: () => Promise.resolve(false),
      getRecentFiles: () => [],
      addRecentFile: () => {},
      getLastFile: () => null,
      getStartupFile: () => null,
    };
    return;
  }

  // Tauri 模式：调用 Rust 命令
  const invoke = (cmd, args) => {
    if (window.__TAURI__ && window.__TAURI__.invoke) {
      return window.__TAURI__.invoke(cmd, args);
    }
    // 兼容 older tauri api
    if (window.__TAURI_IPC__) {
      return window.__TAURI_IPC__(cmd, JSON.stringify(args || {}));
    }
    return Promise.reject('no invoke');
  };

  // 当前打开文件的完整路径（供保存时写回磁盘）
  let currentFilePath = '';

  const bridge = {
    mode: 'tauri',
    get currentFilePath() { return currentFilePath; },
    set currentFilePath(v) { currentFilePath = v || ''; },

    // 通过路径加载 MD 文件
    async loadByPath(path) {
      try {
        const content = await invoke('read_file', { path });
        currentFilePath = path;
        const name = path.split(/[\\\/]/).pop() || 'document.md';
        // 必须先设置当前文件路径，再渲染——
        // 否则 renderMarkdown 中解析相对图片路径时 currentFilePath 为空
        if (typeof window.setCurrentFile === 'function') {
          window.setCurrentFile(name, path);
        }
        if (typeof window.renderMarkdown === 'function') {
          window.renderMarkdown(content);
        }
        // 加入最近文件
        try { bridge.addRecentFile(path); } catch (_) {}
        if (typeof window.toast === 'function') window.toast('已加载: ' + name);
        return content;
      } catch (e) {
        console.error('Tauri read_file failed:', e);
        alert('读取文件失败: ' + e);
        return null;
      }
    },

    // 弹出原生文件选择对话框，返回选中的文件路径（取消返回 null）
    async openFile() {
      try {
        const dialog = window.__TAURI__ && window.__TAURI__.dialog;
        let selected;
        if (dialog && dialog.open) {
          selected = await dialog.open({
            title: '打开 Markdown 文件',
            multiple: false,
            filters: [{ name: 'Markdown', extensions: ['md', 'markdown', 'txt'] }],
          });
        } else {
          // 兼容旧版：通过 invoke 调用 dialog 命令
          selected = await invoke('plugin:dialog|open', {
            options: {
              title: '打开 Markdown 文件',
              multiple: false,
              filters: [{ name: 'Markdown', extensions: ['md', 'markdown', 'txt'] }],
            },
          });
        }
        return selected || null;
      } catch (e) {
        console.error('openFile dialog failed:', e);
        return null;
      }
    },

    // 写入文件到磁盘
    async saveFile(path, contents) {
      if (!path) return false;
      try {
        await invoke('write_file', { path, contents });
        return true;
      } catch (e) {
        console.error('write_file failed:', e);
        alert('保存文件失败: ' + e);
        return false;
      }
    },

    // 获取最近文件列表
    async getRecentFiles() {
      try { return await invoke('get_recent_files'); }
      catch(e) { return []; }
    },
    // 加入最近文件
    async addRecentFile(path) {
      try { return await invoke('add_recent_file', { path }); }
      catch(e) {}
    },
    // 获取上次打开的文件
    async getLastFile() {
      try { return await invoke('get_last_file'); }
      catch(e) { return null; }
    },
    // 获取启动文件（双击 .md 打开）
    async getStartupFile() {
      try { return await invoke('get_startup_file'); }
      catch(e) { return null; }
    },
  };

  window.__TAURI_BRIDGE__ = bridge;

  // 启动后仅加载命令行传入的文件（双击 .md 打开）；不再自动恢复上次文档
  const autoLoad = async () => {
    const startup = await bridge.getStartupFile();
    if (startup) {
      await bridge.loadByPath(startup);
    }
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', autoLoad);
  } else {
    autoLoad();
  }

  // 阻止浏览器默认拖放行为（避免打开 file://）
  window.addEventListener('dragover', (e) => { e.preventDefault(); });
  window.addEventListener('drop', (e) => { e.preventDefault(); });
})();
