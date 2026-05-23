import os
from pathlib import Path
from enum import Enum, unique
from dataclasses import dataclass
from functools import cached_property

from PySide6.QtWidgets import QWidget, QVBoxLayout, QMenu, QAbstractItemView, QTableWidgetItem, QHeaderView
from PySide6.QtCore import Qt, Signal, QModelIndex, QUrl
from qfluentwidgets import TableWidget, BodyLabel, FluentIcon, InfoBar, InfoBarPosition
from PySide6.QtGui import QAction, QColor, QBrush
from showinfm import show_in_file_manager

from backend.config import config, tr
from backend.tools.common_tools import is_image_file

@unique
class TaskStatus(Enum):
    PENDING = tr['TaskList']['Pending']
    PROCESSING = tr['TaskList']['Processing']
    COMPLETED = tr['TaskList']['Completed']
    FAILED = tr['TaskList']['Failed']


@unique
class TaskOptions(Enum):
    AB_SECTIONS = "ab_sections"
    SUB_AREAS = "sub_areas"
    SRT_PATH = "subtitle_srt_path"

@dataclass
class Task:
    path: str
    name: str
    progress: int
    status: TaskStatus
    options: dict
    # 用于储存只读的输出路径, 在任务完成后设置
    _output_path: str = None

    @property
    def output_path(self):
        """获取输出路径"""
        if self._output_path is not None:
            return self._output_path
        save_directory = os.path.dirname(self.path) if not config.saveDirectory.value else config.saveDirectory.value
        if self.is_image:
            output_path = os.path.abspath(os.path.join(save_directory, f'{Path(self.path).stem}_no_sub.png'))
        else:
            output_path = os.path.abspath(os.path.join(save_directory, f'{Path(self.path).stem}_no_sub.mp4'))
        return output_path

    @output_path.setter
    def output_path(self, value):
        self._output_path = value

    @cached_property
    def is_image(self):
        """判断是否是图片文件"""
        return is_image_file(self.path)

class TaskListComponent(QWidget):
    """任务列表组件"""

    # 定义信号
    task_selected = Signal(int, str)  # 任务被选中时发出信号，参数为任务索引和视频路径
    task_deleted = Signal(int)  # 任务被删除时发出信号，参数为任务索引

    # 区域继承信号
    region_copy_requested = Signal(int)                  # 复制 task[row] 的区域到剪贴板
    region_paste_requested = Signal(int)                 # 粘贴剪贴板区域到 task[row]
    region_paste_multi_requested = Signal(list)          # 粘贴剪贴板区域到多个 task[rows]
    region_apply_all_requested = Signal(int)             # 将 task[row] 的区域应用到所有任务
    region_preset_requested = Signal(int, str, str)      # (row, preset_name, areas_str) 单任务
    region_preset_multi_requested = Signal(list, str, str)  # (rows, preset_name, areas_str) 多任务
    region_preset_apply_all_requested = Signal(str, str) # (preset_name, areas_str) 所有任务

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("TaskListComponent")

        # 初始化变量
        self.tasks = []  # 存储任务列表
        self.current_task_index = -1  # 当前选中的任务索引
        self._paste_enabled = False  # 控制"粘贴区域"菜单项是否可用
        self._auto_select_enabled = True  # 是否允许处理进度自动切换表格选中行
        
        # 创建布局
        self.__init_widgets()
        
    def __init_widgets(self):
        """初始化组件"""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        
        # 创建表格
        self.table = TableWidget(self)
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels([tr['TaskList']['Name'], tr['TaskList']['Progress'], tr['TaskList']['Status'], tr['TaskList']['SRT']])
        
        # 设置表格样式
        self.table.setShowGrid(False)
        self.table.setAlternatingRowColors(True)
        
        # 设置列宽模式
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.Stretch)           # 名称列拉伸填充
        header.setSectionResizeMode(1, QHeaderView.ResizeToContents)  # 进度列自适应内容宽度
        header.setSectionResizeMode(2, QHeaderView.ResizeToContents)  # 状态列自适应内容宽度
        header.setSectionResizeMode(3, QHeaderView.ResizeToContents)  # SRT列自适应内容宽度
        
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.ExtendedSelection)  # Ctrl/Shift 多选
        self.table.setEditTriggers(QAbstractItemView.NoEditTriggers)

        # 连接信号
        self.table.setContextMenuPolicy(Qt.CustomContextMenu)
        self.table.customContextMenuRequested.connect(self.show_context_menu)
        self.table.clicked.connect(self.on_task_clicked)
        
        layout.addWidget(self.table)
        
    def add_task(self, video_path):
        """添加任务到列表
        
        Args:
            video_path: 视频文件路径
        """
        # 覆盖相同路径的任务
        for row, task in enumerate(self.tasks[:]):
            if task.path == video_path:
                self.delete_task(row)
                continue
                
        # 获取文件名
        file_name = os.path.basename(video_path)
        
        # 添加到任务列表
        task = Task(
            path=video_path,
            name=file_name,
            progress=0,
            status=TaskStatus.PENDING,
            options={},
        )
        self.tasks.append(task)
        
        # 更新表格
        row = len(self.tasks) - 1
        self.table.setRowCount(len(self.tasks))
        
        item0 = QTableWidgetItem(file_name)
        item1 = QTableWidgetItem("0%")
        item2 = QTableWidgetItem(TaskStatus.PENDING.value)
        item3 = QTableWidgetItem(tr['TaskList']['NoSRT'])
        
        # 设置文件名单元格的省略模式为中间省略
        item0.setTextAlignment(Qt.AlignVCenter | Qt.AlignLeft)
        item0.setToolTip(video_path)  # 设置完整路径为工具提示
        # 设置表格的文本省略模式
        self.table.setTextElideMode(Qt.ElideMiddle)
        
        item1.setTextAlignment(Qt.AlignCenter)
        item2.setTextAlignment(Qt.AlignCenter)
        item3.setTextAlignment(Qt.AlignVCenter | Qt.AlignLeft)
        
        self.table.setItem(row, 0, item0)
        self.table.setItem(row, 1, item1)
        self.table.setItem(row, 2, item2)
        self.table.setItem(row, 3, item3)
        
        # 滚动到最新添加的行
        self.table.scrollToBottom()
        return True
        
    def update_task_progress(self, index, progress):
        """更新任务进度
        
        Args:
            index: 任务索引
            progress: 进度值(0-100)
        """
        if 0 <= index < len(self.tasks):
            self.tasks[index].progress = progress
            
            # 更新进度单元格
            progress_item = self.table.item(index, 1)
            if progress_item:
                progress_item.setText(f"{progress}%")
            
            # 如果是当前处理的任务，滚动到可见区域
            if index == self.current_task_index:
                self.table.scrollTo(self.table.model().index(index, 0))
                
    def update_task_status(self, index, status):
        """更新任务状态
        
        Args:
            index: 任务索引
            status: 任务状态
        """
        if 0 <= index < len(self.tasks):
            self.tasks[index].status = status
            status_item = self.table.item(index, 2)
            if status_item:
                status_item.setText(status.value)
                
                # 根据状态设置不同颜色
                if status == TaskStatus.COMPLETED:
                    status_item.setForeground(QBrush(QColor("#2ecc71")))  # 绿色
                elif status == TaskStatus.PROCESSING:
                    status_item.setForeground(QBrush(QColor("#3498db")))  # 蓝色
                elif status == TaskStatus.FAILED:
                    status_item.setForeground(QBrush(QColor("#e74c3c")))  # 红色
            
            # 如果是当前处理的任务，滚动到可见区域
            if index == self.current_task_index:
                self.table.scrollTo(self.table.model().index(index, 0))
                
            # 选中当前行（用户正在浏览其他任务时仅滚动，不切换选中行）
            if self._auto_select_enabled:
                self.table.selectRow(index)
            else:
                self.table.scrollTo(self.table.model().index(index, 0))
    
    def get_pending_tasks(self):
        """获取所有待处理的任务
        
        Returns:
            list: 待处理任务列表，每项为 (索引, 任务) 元组
        """
        return [(i, task) for i, task in enumerate(self.tasks) if task.status == TaskStatus.PENDING]
    
    def get_all_tasks(self):
        """获取所有任务
        
        Returns:
            list: 所有任务列表
        """
        return self.tasks

    def get_task(self, index):
        """获取指定索引的任务

        Args:
            index: 任务索引

        Returns:
            Task: 任务对象
        """
        if 0 <= index < len(self.tasks):
            return self.tasks[index]
        return None
    
    def find_task_index_by_path(self, path):
        tasks = self.get_all_tasks()
        for idx, task in enumerate(tasks):
            if task.path == path:
                return idx
        return -1  # 没找到返回-1
        
    def show_context_menu(self, pos):
        """显示右键菜单，支持单选和多选"""
        index = self.table.indexAt(pos)
        if not index.isValid():
            return

        right_clicked_row = index.row()
        selected_rows = self.get_selected_rows()

        # 如果右键点击的行不在当前选中集合里，改为仅选中该行
        if right_clicked_row not in selected_rows:
            self.table.selectRow(right_clicked_row)
            selected_rows = [right_clicked_row]

        is_multi = len(selected_rows) > 1
        menu = QMenu(self)

        if is_multi:
            # ── 多选模式 ──────────────────────────────────────────
            n = len(selected_rows)

            # 标题（不可点击，仅作提示）
            title_action = QAction(tr['TaskList']['SelectedCount'].format(n), self)
            title_action.setEnabled(False)
            menu.addAction(title_action)
            menu.addSeparator()

            # 重置所有已选
            reset_sel_action = QAction(tr['TaskList']['ResetSelected'], self)
            reset_sel_action.triggered.connect(
                lambda checked=False, rows=list(selected_rows): self._reset_selected_rows(rows))
            menu.addAction(reset_sel_action)

            # 删除所有已选
            delete_sel_action = QAction(tr['TaskList']['DeleteSelected'].format(n), self)
            delete_sel_action.triggered.connect(
                lambda checked=False, rows=list(selected_rows): self._delete_selected_rows(rows))
            menu.addAction(delete_sel_action)

            # --- 区域 ---
            menu.addSeparator()

            paste_sel_action = QAction(tr['TaskList']['PasteRegionToSelected'].format(n), self)
            paste_sel_action.setEnabled(self._paste_enabled)
            paste_sel_action.triggered.connect(
                lambda checked=False, rows=list(selected_rows): self.region_paste_multi_requested.emit(rows))
            menu.addAction(paste_sel_action)

            presets = self._get_saved_presets()
            if presets:
                preset_sel_menu = QMenu(tr['TaskList']['SetPresetForSelected'].format(n), self)
                for p in presets:
                    act = QAction(p['name'], self)
                    act.triggered.connect(
                        lambda checked=False, rows=list(selected_rows), pname=p['name'], pareas=p['areas']:
                            self.region_preset_multi_requested.emit(rows, pname, pareas)
                    )
                    preset_sel_menu.addAction(act)
                menu.addMenu(preset_sel_menu)

                preset_all_menu = QMenu(tr['TaskList']['ApplyPresetToAll'], self)
                for p in presets:
                    act = QAction(p['name'], self)
                    act.triggered.connect(
                        lambda checked=False, pname=p['name'], pareas=p['areas']:
                            self.region_preset_apply_all_requested.emit(pname, pareas)
                    )
                    preset_all_menu.addAction(act)
                menu.addMenu(preset_all_menu)

        else:
            # ── 单选模式 ──────────────────────────────────────────
            row = right_clicked_row

            open_video_location_action = QAction(tr['TaskList']['OpenSourceVideoLocation'], self)
            open_video_location_action.triggered.connect(lambda: self.open_file_location(self.tasks[row].path))
            menu.addAction(open_video_location_action)

            def open_target_location():
                task = self.tasks[row]
                if task.status != TaskStatus.COMPLETED:
                    InfoBar.warning(
                        title=tr['TaskList']['Warning'],
                        content=tr['TaskList']['TargetFileNotFound'],
                        parent=self.get_root_parent(),
                        duration=3000
                    )
                    return
                self.open_file_location(task.output_path)
            open_target_location_action = QAction(tr['TaskList']['OpenTargetVideoLocation'], self)
            open_target_location_action.triggered.connect(open_target_location)
            menu.addAction(open_target_location_action)

            reset_action = QAction(tr['TaskList']['ResetTaskStatus'], self)
            reset_action.triggered.connect(lambda: (
                self.update_task_status(row, TaskStatus.PENDING),
                self.update_task_progress(row, 0)
            ))
            menu.addAction(reset_action)

            delete_action = QAction(tr['TaskList']['DeleteTask'], self)
            delete_action.triggered.connect(lambda: self.delete_task(row))
            menu.addAction(delete_action)

            # --- 区域继承 ---
            menu.addSeparator()

            copy_region_action = QAction(tr['TaskList']['CopyRegion'], self)
            copy_region_action.triggered.connect(lambda checked=False, r=row: self.region_copy_requested.emit(r))
            menu.addAction(copy_region_action)

            paste_region_action = QAction(tr['TaskList']['PasteRegion'], self)
            paste_region_action.setEnabled(self._paste_enabled)
            paste_region_action.triggered.connect(lambda checked=False, r=row: self.region_paste_requested.emit(r))
            menu.addAction(paste_region_action)

            apply_all_action = QAction(tr['TaskList']['ApplyRegionToAll'], self)
            apply_all_action.triggered.connect(lambda checked=False, r=row: self.region_apply_all_requested.emit(r))
            menu.addAction(apply_all_action)

            # --- 从预设设置区域 ---
            presets = self._get_saved_presets()
            if presets:
                menu.addSeparator()

                preset_menu = QMenu(tr['TaskList']['SetRegionFromPreset'], self)
                for p in presets:
                    act = QAction(p['name'], self)
                    act.triggered.connect(
                        lambda checked=False, r=row, pname=p['name'], pareas=p['areas']:
                            self.region_preset_requested.emit(r, pname, pareas)
                    )
                    preset_menu.addAction(act)
                menu.addMenu(preset_menu)

                preset_all_menu = QMenu(tr['TaskList']['ApplyPresetToAll'], self)
                for p in presets:
                    act = QAction(p['name'], self)
                    act.triggered.connect(
                        lambda checked=False, pname=p['name'], pareas=p['areas']:
                            self.region_preset_apply_all_requested.emit(pname, pareas)
                    )
                    preset_all_menu.addAction(act)
                menu.addMenu(preset_all_menu)

        menu.exec_(self.table.viewport().mapToGlobal(pos))
    
    def delete_task(self, row):
        """删除任务
        
        Args:
            row: 行索引
        """
        if 0 <= row < len(self.tasks):
            # 从列表中删除
            del self.tasks[row]
            
            # 从表格中删除
            self.table.removeRow(row)
                
            # 如果删除的是当前任务，重置当前任务索引
            if row == self.current_task_index:
                self.current_task_index = -1
                
            # 发出任务删除信号
            self.task_deleted.emit(row)
    
    def on_task_clicked(self, index):
        """任务被点击时的处理 — 多选时不切换视频预览"""
        row = index.row()
        if 0 <= row < len(self.tasks):
            self.current_task_index = row
            # 仅当单选时加载对应视频，多选时不切换预览
            if len(self.get_selected_rows()) == 1:
                self.task_selected.emit(row, self.tasks[row].path)
            
    def set_current_task(self, index):
        """设置当前处理的任务
        
        Args:
            index: 任务索引
        """
        if 0 <= index < len(self.tasks):
            self.current_task_index = index
            self.table.selectRow(index)
            self.table.scrollTo(self.table.model().index(index, 0))
        
    def get_current_task_index(self):
        """获取当前处理的任务索引

        Returns:
            int: 任务索引
        """
        return self.current_task_index
            
    def select_task(self, index):
        """选中指定任务
        
        Args:
            index: 任务索引
        """
        self.set_current_task(index)
        if 0 <= index < len(self.tasks):
            self.task_selected.emit(index, self.tasks[index].path)

    def open_file_location(self, path):
        """打开文件所在位置
        
        Args:
            row: 行索引
            path: 目标路径
        """                
        # 检查视频文件是否存在
        if not os.path.exists(path):
            InfoBar.warning(
                title=tr['TaskList']['Warning'],
                content=tr['TaskList']['UnableToLocateFile'],
                parent=self.get_root_parent(),
                duration=3000
            )
            return
            
        show_in_file_manager(os.path.abspath(path))

    def get_root_parent(self):
        parent = self
        while parent.parent():
            parent = parent.parent()
        return parent

    def update_task_option(self, index, task_option: TaskOptions, value):
        """更新任务选项

        Args:
            index: 任务索引
            task_option: 选项名
            value: 选项值
        """
        if 0 <= index < len(self.tasks):
            self.tasks[index].options[task_option.value] = value
            if task_option == TaskOptions.SRT_PATH:
                self.update_task_srt(index, value)
            elif task_option == TaskOptions.SUB_AREAS:
                self._update_region_indicator(index, value)

    def _update_region_indicator(self, index, regions):
        if not (0 <= index < len(self.tasks)):
            return
        name_item = self.table.item(index, 0)
        if not name_item:
            return
        task = self.tasks[index]
        if regions:
            count = len(regions)
            name_item.setForeground(QBrush(QColor("#27ae60")))
            name_item.setToolTip(f"{task.path}\n{tr['TaskList']['RegionApplied'].format(count)}")
        else:
            name_item.setForeground(QBrush())
            name_item.setToolTip(task.path)

    def update_task_srt(self, index, srt_path):
        if not (0 <= index < len(self.tasks)):
            return
        srt_item = self.table.item(index, 3)
        if not srt_item:
            return
        if srt_path:
            srt_name = os.path.basename(srt_path)
            srt_item.setText(srt_name)
            srt_item.setToolTip(srt_path)
            srt_item.setForeground(QBrush(QColor("#2980b9")))
        else:
            srt_item.setText(tr['TaskList']['NoSRT'])
            srt_item.setToolTip("")
            srt_item.setForeground(QBrush(QColor("#888888")))

    def set_paste_enabled(self, enabled: bool):
        """设置'粘贴区域'菜单项是否可用"""
        self._paste_enabled = enabled

    def get_task_option(self, index, task_option: TaskOptions, default=None):
        """获取任务选项
        Args:
            index: 任务索引
            task_option: 选项名
            default: 默认值
        Returns:
            选项值
        """
        if 0 <= index < len(self.tasks):
            return self.tasks[index].options.get(task_option.value, default)

    def set_auto_select_enabled(self, enabled: bool):
        """控制处理进度是否自动切换表格选中行（用户浏览时禁用）"""
        self._auto_select_enabled = enabled

    def scroll_to_row(self, index: int):
        """仅滚动到指定行，不改变选中状态"""
        if 0 <= index < len(self.tasks):
            self.table.scrollTo(self.table.model().index(index, 0))

    def get_selected_rows(self) -> list:
        """返回当前所有选中行的有序索引列表"""
        return sorted(set(idx.row() for idx in self.table.selectedIndexes()))

    def _reset_selected_rows(self, rows: list):
        """重置多个选中任务的状态为 Pending"""
        for row in rows:
            self.update_task_status(row, TaskStatus.PENDING)
            self.update_task_progress(row, 0)

    def _delete_selected_rows(self, rows: list):
        """删除多个选中任务（倒序删除以保证索引不错位）"""
        for row in sorted(rows, reverse=True):
            self.delete_task(row)

    def _get_saved_presets(self) -> list:
        """从 config 读取已保存的预设列表，返回 [{'name': str, 'areas': str}, ...]"""
        raw = config.savedRegionPresets.value or ""
        presets = []
        for entry in raw.split("||"):
            entry = entry.strip()
            if not entry or ":" not in entry:
                continue
            name, _, areas_str = entry.partition(":")
            name = name.strip()
            areas_str = areas_str.strip()
            if name and areas_str:
                presets.append({"name": name, "areas": areas_str})
        return presets
